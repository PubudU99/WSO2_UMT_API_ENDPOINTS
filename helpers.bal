import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

isolated function getPipelineURL(string organization, string project, string pipeline_id) returns string {
    return "https://dev.azure.com/" + organization + "/" + project + "/_apis/pipelines/" + pipeline_id;
}

isolated function getTimelineURL(string organization, string project) returns string {
    return "https://dev.azure.com/" + organization + "/" + project + "/_apis/build/builds";
}

isolated function runTimelineEndpoint() returns http:Client|error {
    http:Client endpoint = check new (getTimelineURL(organization, project), {
        auth: {
            username: "PAT_AZURE_DEVOPS",
            password: PAT_AZURE_DEVOPS
        }
    }
    );
    return endpoint;
}

isolated function pipelineEndpoint(string pipeline_id) returns http:Client|error {
    http:Client endpoint = check new (getPipelineURL(organization, project, pipeline_id), {
        auth: {
            username: "PAT_AZURE_DEVOPS",
            password: PAT_AZURE_DEVOPS
        }
    }
    );
    return endpoint;
}

isolated function getRunTimelineResult(string runId) returns TimelineTask|error {
    http:Client endpoint = check runTimelineEndpoint();
    TimelineTask response = check endpoint->/[runId]/timeline.get(api\-version = "7.0");
    return response;
}

isolated function getRunResult(string runId) returns json {
    do {
        http:Client endpoint = check pipelineEndpoint(ciPipelineId);
        json response = check endpoint->/runs/[runId].get(api\-version = "7.1-preview.1");
        return response;
    } on fail var e {
        io:println("Error in function getRunResult");
        io:println(e);
    }
}

isolated function getAcrEndpoint() returns http:Client|error {
    http:Client clientEndpoint = check new ("https://cstimage.azurecr.io/acr/v1", {
        auth: {
            username: acrUsername,
            password: acrPassword
        }
    });
    return clientEndpoint;
}

isolated function triggerAzureEndpointCiBuild(string product, string version, string updateType, string updateLevel = "") returns json {
    do {
        http:Client pipeline = check pipelineEndpoint(ciPipelineId);
        json response;
        if !updateLevel.equalsIgnoreCaseAscii("") {
            response = check pipeline->/runs.post({
                    templateParameters: {
                        product: product,
                        version: version,
                        customer_update_level: updateLevel,
                        update_type: updateType
                    }
                },
                api\-version = "7.1-preview.1"
            );
        } else {
            response = check pipeline->/runs.post({
                    templateParameters: {
                        product: product,
                        version: version,
                        update_type: updateType
                    }

                },
                api\-version = "7.1-preview.1"
            );
        }
        return response;
    } on fail var e {
        io:println("Error in function triggerAzureEndpointCiBuild");
        io:println(e);
    }
}

isolated function triggerAzureEndpointCdBuild(string customer, string helmOverideValuesString) returns json {
    do {
        http:Client pipeline = check pipelineEndpoint(cdPipelineId);
        json response = check pipeline->/runs.post({
                templateParameters: {
                    customer: customer,
                    helm_overide_value_string: helmOverideValuesString
                }
            },
            api\-version = "7.1-preview.1"
        );
        return response;
    } on fail var e {
        io:println("Error in function triggerAzureEndpointCdBuild");
        io:println(e);
    }
}

isolated function getMapCiIdState(map<int> mapProductCiId) returns map<string> {
    map<string> mapCiIdState = {};
    foreach string product in mapProductCiId.keys() {
        int ciId = mapProductCiId.get(product);
        json run = getRunResult(ciId.toString());
        string runState = check run.state;
        sql:ParameterizedQuery whereClause = `ci_build_id = ${ciId}`;
        stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, whereClause);
        var ciBuildResponse = check response.next();
        if ciBuildResponse !is error? {
            json ciBuildResponseJson = check ciBuildResponse.value.fromJsonWithType();
            string ciBuildRecordId = check ciBuildResponseJson.id;
            if runState.equalsIgnoreCaseAscii("completed") {
                string runResult = check run.result;
                ci_build _ = check sClient->/ci_builds/[ciBuildRecordId].put({
                    ci_status: runResult
                });
                mapCiIdState[ciId.toString()] = runResult;
            } else {
                mapCiIdState[ciId.toString()] = runState;
            }
        }
    } on fail var e {
        io:println("Error in function get_mapCiIdState");
        io:println(e);
    }
    return mapCiIdState;
}

isolated function initializeClient() returns Client|persist:Error {
    return new Client();
}

isolated function getCustomersToInsert(CustomerInsertCopy[] list) returns customerInsert[] {
    customerInsert[] cst_info_list = [];

    foreach CustomerInsertCopy item in list {

        customerInsert tmp = {
            id: uuid:createType4AsString(),
            customer_key: item.customerKey,
            environment: item.environment,
            product_name: item.productName,
            product_base_version: item.productBaseversion,
            u2_level: item.u2Level
        };

        cst_info_list.push(tmp);
    }

    return cst_info_list;
}

isolated function createProductWhereClause(ProductRegularUpdate[] product_list) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery whereClause = ``;
    int i = 0;
    while i < product_list.length() {
        if (i == product_list.length() - 1) {
            whereClause = sql:queryConcat(whereClause, `(product_name = ${product_list[i].productName} AND product_base_version = ${product_list[i].productBaseversion})`);
        } else {
            whereClause = sql:queryConcat(whereClause, `(product_name = ${product_list[i].productName} AND product_base_version = ${product_list[i].productBaseversion}) OR `);
        }
        i += 1;
    }
    return whereClause;
}

isolated function insertCicdBuild(string uuid) returns cicd_buildInsert|error {
    cicd_buildInsert[] cicdBuildInsertList = [];

    cicd_buildInsert tmp = {
        id: uuid,
        ci_result: "inProgress",
        cd_result: "pending"
    };

    cicdBuildInsertList.push(tmp);

    string[] _ = check sClient->/cicd_builds.post(cicdBuildInsertList);

    return tmp;
}

isolated function createMapCustomerCiList(string[] product_list, map<int> mapProductCiId) returns map<string[]> {
    map<string[]> mapCustomerProduct = {};
    // If the product list is type ProductRegularUpdate
    foreach string product in product_list {
        // selecting the customers whose deployment has the specific update products
        string productName = regex:split(product, "-")[0];
        string version = regex:split(product, "-")[1];
        sql:ParameterizedQuery whereClauseProduct = `(product_name = ${productName} AND product_base_version = ${version})`;
        stream<customer, persist:Error?> response = sClient->/customers.get(customer, whereClauseProduct);
        var customerStreamItem = response.next();
        int customerProductCiId = <int>mapProductCiId[product];
        // Iterate on the customer list and maintaining a map to record which builds should be completed for a spcific customer to start tests
        while customerStreamItem !is error? {
            json customer = check customerStreamItem.value.fromJsonWithType();
            string customerName = check customer.customer_key;
            string[] tmp;
            if mapCustomerProduct.hasKey(customerName) {
                tmp = mapCustomerProduct.get(customerName);
                tmp.push(customerProductCiId.toString());
            } else {
                tmp = [];
                tmp.push(customerProductCiId.toString());
            }
            mapCustomerProduct[customerName] = tmp;
            customerStreamItem = response.next();
        } on fail var e {
            io:println("Error in function create_customer_product_map");
            io:println(e);
        }
    }
    return mapCustomerProduct;
}

isolated function getCiPendingCicdIdList(sql:ParameterizedQuery whereClause) returns string[] {
    string[] idList = [];
    stream<cicd_build, persist:Error?> cicdResponseStream = sClient->/cicd_builds.get(cicd_build, whereClause);
    var cicdResponse = cicdResponseStream.next();
    while cicdResponse !is error? {
        json cicdResponseJson = check cicdResponse.value.fromJsonWithType();
        string id = check cicdResponseJson.id;
        idList.push(id);
        cicdResponse = cicdResponseStream.next();
    } on fail var e {
        io:println("Error in function get_pending_ci_idList ");
        io:println(e);
    }
    return idList;
}

isolated function updateCiStatus(string[] idList) {
    do {
        http:Client pipeline = check pipelineEndpoint(ciPipelineId);
        sql:ParameterizedQuery whereClause = ``;
        int i = 0;
        foreach string id in idList {
            if (i == idList.length() - 1) {
                whereClause = sql:queryConcat(whereClause, `cicd_buildId = ${id}`);
            } else {
                whereClause = sql:queryConcat(whereClause, `cicd_buildId = ${id} OR `);
            }
            i += 1;
        }
        stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, whereClause);
        var ciBuildResponse = response.next();
        while ciBuildResponse !is error? {
            json ciBuildResponseJson = check ciBuildResponse.value.fromJsonWithType();
            int ciBuildId = check ciBuildResponseJson.ci_build_id;
            string ciId = check ciBuildResponseJson.id;
            json runResponse = check pipeline->/runs/[ciBuildId].get(api\-version = "7.1-preview.1");
            string runState = check runResponse.state;
            string runResult;
            if ("completed".equalsIgnoreCaseAscii(runState)) {
                runResult = check runResponse.result;
            } else {
                runResult = check runResponse.state;
            }
            ci_build _ = check sClient->/ci_builds/[ciId].put({
                ci_status: runResult
            });
            ciBuildResponse = response.next();
        }
    } on fail var e {
        io:println("Error in function update_ci_status");
        io:println(e);
    }
}

isolated function updateCiStatusCicdTable(string[] idList) {
    do {
        foreach string id in idList {
            sql:ParameterizedQuery whereClause = `cicd_buildId = ${id}`;
            stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, whereClause);
            var ciBuildResponse = response.next();
            boolean allSucceededFlag = true;
            boolean anyBuildFailed = false;
            boolean stillInProgress = false;
            while ciBuildResponse !is error? {
                json ciBuildResponseJson = check ciBuildResponse.value.fromJsonWithType();
                string ciBuildStatus = check ciBuildResponseJson.ci_status;
                if (!ciBuildStatus.equalsIgnoreCaseAscii("succeeded") && !ciBuildStatus.equalsIgnoreCaseAscii("inProgress")) {
                    allSucceededFlag = false;
                }
                if (ciBuildStatus.equalsIgnoreCaseAscii("failed")) {
                    anyBuildFailed = true;
                }
                if (ciBuildStatus.equalsIgnoreCaseAscii("inProgress")) {
                    allSucceededFlag = false;
                    stillInProgress = true;
                }
                ciBuildResponse = response.next();
            }
            if allSucceededFlag {
                cicd_build _ = check sClient->/cicd_builds/[id].put({
                    ci_result: "succeeded"
                });
            }
            if anyBuildFailed && !stillInProgress {
                cicd_build _ = check sClient->/cicd_builds/[id].put({
                    ci_result: "failed"
                });
            }
        }
    } on fail var e {
        io:println("Error in function update_parent_ci_status");
        io:println(e);
    }
}

isolated function getMapProductCiId(string cicdId) returns map<int> {
    sql:ParameterizedQuery whereClause = `cicd_buildId = ${cicdId}`;
    stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, whereClause);
    map<int> mapProductCiId = {};
    var ciBuildRepsonse = response.next();
    while ciBuildRepsonse !is error? {
        json ciBuildRepsonseJson = check ciBuildRepsonse.value.fromJsonWithType();
        string productName = check ciBuildRepsonseJson.product;
        string version = check ciBuildRepsonseJson.version;
        int ciBuildId = check ciBuildRepsonseJson.ci_build_id;
        mapProductCiId[string:'join("-", productName, version)] = ciBuildId;
        ciBuildRepsonse = response.next();
    } on fail var e {
        io:println("Error in function get_mapProductCiId");
        io:println(e);
    }
    return mapProductCiId;
}

isolated function updateCdResultCicdParentTable() {
    do {
        stream<cicd_build, persist:Error?> cicdResponse = sClient->/cicd_builds.get(cicd_build, `cd_result = "inProgress"`);
        var cicdBuildResponse = cicdResponse.next();
        while cicdBuildResponse !is error? {
            json cicdResponseJson = check cicdBuildResponse.value.fromJsonWithType();
            string cicdId = check cicdResponseJson.id;
            boolean allSucceededFlag = true;
            boolean anyBuildFailedFlag = false;
            boolean stillInPrgressFlag = false;
            stream<cd_build, persist:Error?> cdResponseStream = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId}`);
            var cdResponse = cdResponseStream.next();
            while cdResponse !is error? {
                json cdResponseJson = check cdResponse.value.fromJsonWithType();
                string cdStatus = check cdResponseJson.cd_status;
                if cdStatus.equalsIgnoreCaseAscii("failed") && !cdStatus.equalsIgnoreCaseAscii("inProgress") {
                    anyBuildFailedFlag = true;
                    allSucceededFlag = false;
                    break;
                }
                if cdStatus.equalsIgnoreCaseAscii("inProgress") {
                    allSucceededFlag = false;
                    stillInPrgressFlag = true;
                    break;
                }
                cdResponse = cdResponseStream.next();
            }
            if anyBuildFailedFlag && !stillInPrgressFlag {
                cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                    cd_result: "failed"
                });
            }
            if allSucceededFlag {
                cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                    cd_result: "succeeded"
                });
            }
            cicdBuildResponse = cicdResponse.next();
        }
    } on fail var e {
        io:println("Error in function updateCdResultCicdParentTable");
        io:println(e);
    }

}

isolated function updateCdResultCicdTable(string cicdId) {
    do {
        stream<cicd_build, persist:Error?> cicdResponse = sClient->/cicd_builds.get(cicd_build, `id = ${cicdId}`);
        var cicdBuildResponse = cicdResponse.next();
        if cicdBuildResponse !is error? {
            json cicdResponseJson = check cicdBuildResponse.value.fromJsonWithType();
            string cdResult = check cicdResponseJson.cd_result;
            if cdResult.equalsIgnoreCaseAscii("pending") {
                cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                    cd_result: "inProgress"
                });
            } else if cdResult.equalsIgnoreCaseAscii("inProgress") {
                boolean allSucceededFlag = true;
                boolean anyBuildFailedFlag = false;
                stream<cd_build, persist:Error?> cdResponseStream = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId}`);
                var cdResponse = cdResponseStream.next();
                while cdResponse !is error? {
                    json cdResponseJson = check cdResponse.value.fromJsonWithType();
                    string cdStatus = check cdResponseJson.cd_status;
                    if cdStatus.equalsIgnoreCaseAscii("failed") && !cdStatus.equalsIgnoreCaseAscii("inProgress") {
                        anyBuildFailedFlag = true;
                        allSucceededFlag = false;
                        break;
                    }
                    if cdStatus.equalsIgnoreCaseAscii("inProgress") {
                        allSucceededFlag = false;
                        break;
                    }
                    cdResponse = cdResponseStream.next();
                }
                if anyBuildFailedFlag {
                    cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                        cd_result: "failed"
                    });
                }
                if allSucceededFlag {
                    cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                        cd_result: "succeeded"
                    });
                }
            }

        }
    } on fail var e {
        io:println("Error is function update_cd_result_cicd_table");
        io:println(e);
    }
}

isolated function getCustomerUsingProducts(string customerName) returns string[] {
    string[] customerUsingProducts = [];
    stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(customer_key = ${customerName})`);
    var customerResponse = customerResponseStream.next();
    while customerResponse !is error? {
        json customerResponseJson = check customerResponse.value.fromJsonWithType();
        string product = check customerResponseJson.product_name;
        string version = check customerResponseJson.product_base_version;
        customerUsingProducts.push(string:'join("-", product, version));
        customerResponse = customerResponseStream.next();
    } on fail var e {
        io:println("Error in resource function getCustomerUsingProducts.");
        io:println(e);
    }
    return customerUsingProducts;
}

isolated function getCustomerProductImageList(string cicdId, string customerName) returns string {
    string[] customerUsingProducts = getCustomerUsingProducts(customerName);
    int i = 0;
    while (i < customerUsingProducts.length()) {
        string product = customerUsingProducts[i];
        string productName = regex:split(product, "-")[0];
        string version = regex:split(product, "-")[1];
        stream<ci_build, persist:Error?> ciResponseStream = sClient->/ci_builds.get(ci_build, `cicd_buildId = ${cicdId} AND product = ${productName} AND version = ${version}`);
        var ciReponse = ciResponseStream.next();
        if ciReponse !is error? {
            json ciReponseJson = check ciReponse.value.fromJsonWithType();
            string updateLevel = check ciReponseJson.update_level;
            if updateLevel.equalsIgnoreCaseAscii("latest_test_level") || updateLevel.equalsIgnoreCaseAscii("hotfix_update_level") {
                int ciBuildId = check ciReponseJson.ci_build_id;
                string tmp = string:'join("-", product, ciBuildId.toString());
                customerUsingProducts[i] = tmp;
            } else {
                string tmp = string:'join(".", product, updateLevel);
                customerUsingProducts[i] = tmp;
            }
        } else {
            stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(customer_key = ${customerName} AND product_name = ${productName} AND product_base_version = ${version})`);
            var customerResponse = customerResponseStream.next();
            if customerResponse !is error? {
                json customerReponseJson = check customerResponse.value.fromJsonWithType();
                string updateLevel = check customerReponseJson.u2_level;
                string tmp = string:'join(".", product, updateLevel.toString());
                customerUsingProducts[i] = tmp;
            }
        }
        i = i + 1;
    } on fail var e {
        io:println("Error in resource function getCustomerProductImageList second while.");
        io:println(e);
    }
    return string:'join(",", ...customerUsingProducts);
}

isolated function getHelmOverideValueString(string productImageString) returns string {
    string[] productImageList = regex:split(productImageString, ",");
    string[] overideValueList = [];
    foreach string productImage in productImageList {
        string product = regex:split(productImage, "-")[0];
        string tmp = "wso2.deployment." + product + ".imageName=" + productImage;
        overideValueList.push(tmp);
    }
    return string:'join(",", ...overideValueList);
}

isolated function insertNewCdBuilds(string cicdId, string customer) {
    do {
        stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId} and customer = ${customer}`);
        var cdBuildResponse = cd_response.next();
        if cdBuildResponse is error? {
            string productImageString = getCustomerProductImageList(cicdId, customer);
            string helmOverideValuesString = getHelmOverideValueString(productImageString);
            json response = triggerAzureEndpointCdBuild(customer, helmOverideValuesString);
            int cdRunId = check response.id;
            string cdRunState = check response.state;
            cd_buildInsert[] tmp = [
                {
                    id: uuid:createType4AsString(),
                    cd_build_id: cdRunId,
                    cd_status: cdRunState,
                    customer: customer,
                    cicd_buildId: cicdId
                }
            ];
            string[] _ = check sClient->/cd_builds.post(tmp);
            io:println("Start CD pipeline of customer " + customer);
            io:println("Create an entry in cd_build table");
        }
    } on fail var e {
        io:println("Error is function insertNewCdBuilds");
        io:println(e);
    }
}

isolated function updateInProgressCdBuilds() {
    stream<cd_build, persist:Error?> cdBuildStream = sClient->/cd_builds.get(cd_build, `cd_status = "inProgress"`);
    var cdBuildResponse = cdBuildStream.next();
    while cdBuildResponse !is error? {
        json cdBuildResponseJson = check cdBuildResponse.value.fromJsonWithType();
        int cd_build_id = check cdBuildResponseJson.cd_build_id;
        string cdBuildRecordId = check cdBuildResponseJson.id;
        json run = getRunResult(cd_build_id.toString());
        string runState = check run.state;
        if runState.equalsIgnoreCaseAscii("completed") {
            string runResult = check run.result;
            cd_build _ = check sClient->/cd_builds/[cdBuildRecordId].put({
                cd_status: runResult
            });
        }
        cdBuildResponse = cdBuildStream.next();
    } on fail var e {
        io:println("Error is function update_inProgress_cd_builds");
        io:println(e);
    }
}

isolated function retriggerFailedCiBuilds(string cicdId) {
    stream<ci_build, persist:Error?> ciResponseStream = sClient->/ci_builds.get(ci_build, `cicd_buildId = ${cicdId} and ci_status = "failed"`);
    var ciResponse = ciResponseStream.next();
    while ciResponse !is error? {
        json ciRepsonseJson = check ciResponse.value.fromJsonWithType();
        string ciBuildRecordId = check ciRepsonseJson.id;
        string product = check ciRepsonseJson.product;
        string version = check ciRepsonseJson.version;
        string updateLevel = check ciRepsonseJson.update_level;
        json response;
        if updateLevel.equalsIgnoreCaseAscii("hotfix_update_level") {
            int ciId = check ciRepsonseJson.ci_build_id;
            json run = getRunResult(ciId.toString());
            string customerUpdateLevel = check run.templateParameters.customer_update_level;
            response = triggerAzureEndpointCiBuild(product, version, "hotfix update", customerUpdateLevel);
        } else if updateLevel.equalsIgnoreCaseAscii("latest_test_level") {
            response = triggerAzureEndpointCiBuild(product, version, "regular update");
        } else {
            int ciId = check ciRepsonseJson.ci_build_id;
            json run = getRunResult(ciId.toString());
            string customerUpdateLevel = check run.templateParameters.customer_update_level;
            response = triggerAzureEndpointCiBuild(product, version, "regular update", customerUpdateLevel);
        }
        int ciRunId = check response.id;
        ci_build _ = check sClient->/ci_builds/[ciBuildRecordId].put({
            ci_status: "inProgress",
            ci_build_id: ciRunId
        });
        ciResponse = ciResponseStream.next();
    } on fail var e {
        io:println("Error in resource function retrigger_failed_ci_builds.");
        io:println(e);
    }
}

isolated function updateCiCdStatusOnRetriggerCiBuilds(string cicdId) {
    stream<cicd_build, persist:Error?> cicdResponse = sClient->/cicd_builds.get(cicd_build, `id = ${cicdId}`);
    var cicdBuildResponse = cicdResponse.next();
    while cicdBuildResponse !is error? {
        cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
            ci_result: "inProgress",
            cd_result: "pending"
        });
        cicdBuildResponse = cicdResponse.next();
    } on fail var e {
        io:println("Error in resource function update_ci_cd_status_on_retrigger_ci_builds.");
        io:println(e);
    }
}

isolated function deleteFailedCdBuilds(string cicdId) {
    stream<cd_build, persist:Error?> cdResponse = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId} and cd_status = "failed"`);
    var cdBuildResponse = cdResponse.next();
    while cdBuildResponse !is error? {
        json cdBuildRepsonseJson = check cdBuildResponse.value.fromJsonWithType();
        string cdBuildRecordId = check cdBuildRepsonseJson.id;
        cd_build _ = check sClient->/cd_builds/[cdBuildRecordId].delete;
        cdBuildResponse = cdResponse.next();
    } on fail var e {
        io:println("Error in resource function delete_failed_cd_builds.");
        io:println(e);
    }
}

isolated function getUniqueList(string[] s) returns string[] {
    map<()> m = {};
    foreach var i in s {
        m[i] = ();
    }
    string[] unique = m.keys();
    return unique;
}

isolated function getProductListForInvolvedCustomerUpdateLevel(ProductRegularUpdate[] product_updates) returns string[] {
    string[] customer_list = [];
    foreach ProductRegularUpdate product in product_updates {
        string productName = product.productName;
        string version = product.productBaseversion;
        stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(product_name = ${productName} AND product_base_version = ${version})`);
        var customerStreamItem = customerResponseStream.next();
        while customerStreamItem !is error? {
            json customer = check customerStreamItem.value.fromJsonWithType();
            string customerName = check customer.customer_key;
            customer_list.push(customerName);
            customerStreamItem = customerResponseStream.next();
        } on fail var e {
            io:println("Error in resource function getCustomerListForUpdates.");
            io:println(e);
        }
    }
    string[] customersInvolved = getUniqueList(customer_list);
    string[] productsInvolved = [];

    foreach string customerName in customersInvolved {
        sql:ParameterizedQuery whereClause = ``;
        foreach ProductRegularUpdate product in product_updates {
            string productName = product.productName;
            string version = product.productBaseversion;
            whereClause = sql:queryConcat(whereClause, `NOT(product_name = ${productName} AND product_base_version = ${version}) AND `);
        }
        whereClause = sql:queryConcat(whereClause, `customer_key = ${customerName}`);
        stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, whereClause);
        var customerResponse = customerResponseStream.next();
        while customerResponse !is error? {
            json customerResponseJson = check customerResponse.value.fromJsonWithType();
            string updateLevel = check customerResponseJson.u2_level;
            string productName = check customerResponseJson.product_name;
            string version = check customerResponseJson.product_base_version;
            string productInvolved = string:'join("-", productName, version);
            productInvolved = string:'join(".", productInvolved, updateLevel);
            productsInvolved.push(productInvolved);
            customerResponse = customerResponseStream.next();
        } on fail var e {
            io:println("Error in resource function getCustomerListForUpdates.");
            io:println(e);
        }
    }
    return getUniqueList(productsInvolved);
}

isolated function getImageNotInACR(string[] productImages) returns string[] {
    string[] productImagesNotInACR = [];
    do {
        string[] acrImageList = getImageInACR();

        foreach string product in productImages {
            boolean imageInAcr = false;
            foreach string acrImage in acrImageList {
                if acrImage.equalsIgnoreCaseAscii(product) {
                    imageInAcr = true;
                    break;
                }
            }
            if !imageInAcr {
                productImagesNotInACR.push(product);
            }
        }
    } on fail var e {
        io:println("Error in resource function getImageNotInACR.");
        io:println(e);
    }
    return productImagesNotInACR;
}

isolated function getImageInACR() returns string[] {
    string[] imageList = [];
    do {
        http:Client acrEndpoint = check getAcrEndpoint();
        AcrImageList acrImages = check acrEndpoint->/_catalog.get();
        imageList = acrImages.repositories ?: [];
    } on fail var e {
        io:println("Error in resource function getImageInACR.");
        io:println(e);
    }
    return imageList;
}

isolated function getProductImageForCustomerUpdateLevel() returns string[] {
    string[] productImageListForCustomerupdateLevel = [];
    stream<customer, persist:Error?> customerResponseStream = sClient->/customers;
    var customerStreamItem = customerResponseStream.next();
    while customerStreamItem !is error? {
        json customer = check customerStreamItem.value.fromJsonWithType();
        string productName = check customer.product_name;
        string version = check customer.product_base_version;
        string updateLevel = check customer.u2_level;
        string imageName = string:'join("-", productName, string:'join(".", version, updateLevel));
        productImageListForCustomerupdateLevel.push(imageName);
        customerStreamItem = customerResponseStream.next();
    } on fail var e {
        io:println("Error in resource function getProductImageForCustomerUpdateLevel.");
        io:println(e);
    }
    return productImageListForCustomerupdateLevel;
}

isolated function getFilteredProductUpdates(ProductRegularUpdate[] productList) returns ProductRegularUpdate[] {
    ProductRegularUpdate[] filteredProducts = [];
    foreach ProductRegularUpdate product in productList {
        stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(product_name = ${product.productName} AND product_base_version = ${product.productBaseversion})`);
        var customerResponse = customerResponseStream.next();
        if customerResponse !is error? {
            filteredProducts.push(product);
        }
    }
    return filteredProducts;
}

isolated function getCiBuildinfo(string cicdId) returns CiBuildInfo[] {
    CiBuildInfo[] ciBuildList = [];
    stream<ci_build, persist:Error?> ciResponseStream = sClient->/ci_builds.get(ci_build, `cicd_buildId = ${cicdId}`);
    var ciBuildResponse = ciResponseStream.next();
    while ciBuildResponse !is error? {
        json ciBuildResponseJson = check ciBuildResponse.value.fromJsonWithType();
        string product = check ciBuildResponseJson.product;
        string version = check ciBuildResponseJson.version;
        string buildStatus = check ciBuildResponseJson.ci_status;
        int ciBuildId = check ciBuildResponseJson.ci_build_id;
        string consoleErrorUrl = "";
        if buildStatus.equalsIgnoreCaseAscii("failed") {
            TimelineTask runTimelineResult = check getRunTimelineResult(ciBuildId.toString());
            TimelineRecord[] runTimelineRecordList = runTimelineResult.records;
            TimelineRecord[] failedRunTimelineRecordList = runTimelineRecordList.filter(item => item.result == "failed");
            consoleErrorUrl = check failedRunTimelineRecordList[0].toJson().log.url;
        }
        CiBuildInfo tmp = {
            product: product,
            version: version,
            status: buildStatus,
            consoleErrorUrl: consoleErrorUrl
        };
        ciBuildList.push(tmp);
        ciBuildResponse = ciResponseStream.next();
    } on fail var e {
        io:println("Error in resource function getCiBuildinfo.");
        io:println(e);
    }
    return ciBuildList;
}

isolated function getCdBuildinfo(string cicdId) returns CdBuildInfo[]|error {
    CdBuildInfo[] cdBuildList = [];
    stream<cd_build, persist:Error?> cdResponseStream = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId}`);
    var cdBuildResponse = cdResponseStream.next();
    while cdBuildResponse !is error? {
        json cdBuildResponseJson = check cdBuildResponse.value.fromJsonWithType();
        string customer = check cdBuildResponseJson.customer;
        string buildStatus = check cdBuildResponseJson.cd_status;
        int cdBuildId = check cdBuildResponseJson.cd_build_id;
        string consoleErrorUrl = "";
        if buildStatus.equalsIgnoreCaseAscii("failed") {
            if cdBuildId == -1 {
                consoleErrorUrl = "Related CI builds failed";
            } else {
                TimelineTask runTimelineResult = check getRunTimelineResult(cdBuildId.toString());
                TimelineRecord[] runTimelineRecordList = runTimelineResult.records;
                TimelineRecord[] failedRunTimelineRecordList = runTimelineRecordList.filter(item => item.result == "failed");
                consoleErrorUrl = check failedRunTimelineRecordList[0].toJson().log.url;
            }
        }
        CdBuildInfo tmp = {
            customer: customer,
            status: buildStatus,
            consoleErrorUrl: consoleErrorUrl
        };
        cdBuildList.push(tmp);
        cdBuildResponse = cdResponseStream.next();
    } on fail var e {
        io:println("Error in resource function getCdBuildinfo.");
        io:println(e);
    }
    return cdBuildList;
}
