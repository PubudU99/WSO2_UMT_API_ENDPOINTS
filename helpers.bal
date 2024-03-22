import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

type CustomerInsertCopy record {|
    string customer_key;
    string environment;
    string productName;
    string productBaseversion;
    string u2Level;
|};

type CiBuildCopy record {|
    string id;
    string ciBuildId;
    string ciStatus;
    string product;
    string version;

    // many-to-one relationship with cicd_build
    cicd_build cicdBuild;
|};

type ProductRegularUpdate record {|
    string productName;
    string productBaseversion;
|};

type ProductHotfixUpdate record {|
    string productName;
    string productBaseVersion;
    string u2Level;
|};

isolated function getRunResult(string runId) returns json {
    do {
        http:Client pipeline = check pipelineEndpoint(ci_pipeline_id);
        json response = check pipeline->/runs/[runId].get(api\-version = "7.1-preview.1");
        return response;
    } on fail var e {
        io:println("Error in function getRunResult");
        io:println(e);
    }
}

isolated function triggerAzureEndpoint(string product, string version) returns json {
    do {
        http:Client pipeline = check pipelineEndpoint(ci_pipeline_id);
        json response = check pipeline->/runs.post({
                templateParameters: {
                    product: product,
                    version: version
                }
            },
            api\-version = "7.1-preview.1"
        );
        return response;
    } on fail var e {
        io:println("Error in function triggerAzureEndpoint");
        io:println(e);
    }
}

isolated function getMapCiIdState(map<int> mapProductCiId) returns map<string> {
    map<string> mapCiIdState = {};
    foreach string product in mapProductCiId.keys() {
        int ciId = mapProductCiId.get(product);
        json run = getRunResult(ciId.toString());
        string runState = check run.state;
        sql:ParameterizedQuery whereClause = `ciBuildId = ${ciId}`;
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
            customer_key: item.customer_key,
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

isolated function getPipelineURL(string organization, string project, string pipeline_id) returns string {
    return "https://dev.azure.com/" + organization + "/" + project + "/_apis/pipelines/" + pipeline_id;
}

isolated function pipelineEndpoint(string pipeline_id) returns http:Client|error {
    http:Client clientEndpoint = check new (getPipelineURL(organization, project, pipeline_id), {
        auth: {
            username: "PAT_AZURE_DEVOPS",
            password: PAT_AZURE_DEVOPS
        }
    }
    );
    return clientEndpoint;
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

isolated function getCiPendingCicdIdList() returns string[] {
    sql:ParameterizedQuery whereClause = `ci_result = "inProgress"`;
    string[] idList = [];
    stream<cicd_build, persist:Error?> response = sClient->/cicd_builds.get(cicd_build, whereClause);
    var idResponse = response.next();
    while idResponse !is error? {
        json idRecord = check idResponse.value.fromJsonWithType();
        string id = check idRecord.id;
        idList.push(id);
        idResponse = response.next();
    } on fail var e {
        io:println("Error in function get_pending_ci_idList ");
        io:println(e);
    }
    return idList;
}

isolated function updateCiStatus(string[] idList) {
    do {
        http:Client pipeline = check pipelineEndpoint(ci_pipeline_id);
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
            int ciBuildId = check ciBuildResponseJson.ciBuildId;
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
        } on fail var e {
            io:println("Error in function get_idList ");
            io:println(e);
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
            boolean allCompletedFlag = true;
            while ciBuildResponse !is error? {
                json ciBuildResponseJson = check ciBuildResponse.value.fromJsonWithType();
                string ciBuildStatus = check ciBuildResponseJson.ci_status;
                if (!ciBuildStatus.equalsIgnoreCaseAscii("succeeded") && !ciBuildStatus.equalsIgnoreCaseAscii("failed")) {
                    allCompletedFlag = false;
                }
                if (!ciBuildStatus.equalsIgnoreCaseAscii("succeeded")) {
                    allSucceededFlag = false;
                }
                ciBuildResponse = response.next();
            }
            if allCompletedFlag {
                stream<cd_build, persist:Error?> cdResponse = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${id}`);
                var cicdBuildResponse = check cdResponse.next();
                if cicdBuildResponse is error? {
                    cicd_build _ = check sClient->/cicd_builds/[id].put({
                        ci_result: "failed",
                        cd_result: "canceled"
                    });
                }
            }
            if allSucceededFlag {
                cicd_build _ = check sClient->/cicd_builds/[id].put({
                    ci_result: "succeeded"
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
        int ciBuildId = check ciBuildRepsonseJson.ciBuildId;
        mapProductCiId[string:'join("-", productName, version)] = ciBuildId;
        ciBuildRepsonse = response.next();
    } on fail var e {
        io:println("Error in function get_mapProductCiId");
        io:println(e);
    }
    return mapProductCiId;
}

isolated function updateCdResultCicdTable(string cicdId) {
    do {
        stream<cicd_build, persist:Error?> cicdResponse = sClient->/cicd_builds.get(cicd_build, `id = ${cicdId} and cd_result = "pending"`);
        var cicdBuildResponse = check cicdResponse.next();
        if cicdBuildResponse !is error? {
            cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                cd_result: "inProgress"
            });
        }
    } on fail var e {
        io:println("Error is function update_cd_result_cicd_table");
        io:println(e);
    }
}

isolated function insertNewCdBuilds(string cicdId, string customer) {
    stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId} and customer = ${customer}`);
    var cdBuildResponse = cd_response.next();
    if cdBuildResponse is error? {
        cd_buildInsert[] tmp = [
            {
                id: uuid:createType4AsString(),
                cd_build_id: "",
                cd_status: "inProgress",
                customer: customer,
                cicd_buildId: cicdId
            }
        ];
        do {
            string[] _ = check sClient->/cd_builds.post(tmp);
        } on fail var e {
            io:println("Error is function update_cd_result_cicd_table");
            io:println(e);
        }
        io:println("Start CD pipeline of customer " + customer);
        io:println("Create an entry in cd_build table");
    }
}

isolated function updateInProgressCdBuilds() {
    stream<cd_build, persist:Error?> response = sClient->/cd_builds.get(cd_build, `cd_status = "inProgress"`);
    var cdBuildStreamItem = response.next();
    while cdBuildStreamItem !is error? {
        json cdBuildStreamItemJson = check cdBuildStreamItem.value.fromJsonWithType();
        string cd_build_id = check cdBuildStreamItemJson.cd_build_id;
        string cdBuildRecordId = check cdBuildStreamItemJson.id;
        json run = getRunResult(cd_build_id);
        string runState = check run.state;
        if runState.equalsIgnoreCaseAscii("completed") {
            string runResult = check run.result;
            ci_build _ = check sClient->/ci_builds/[cdBuildRecordId].put({
                ci_status: runResult
            });
        }
    } on fail var e {
        io:println("Error is function update_inProgress_cd_builds");
        io:println(e);
    }
}

isolated function retriggerFailedCiBuilds(string cicdId) {
    stream<ci_build, persist:Error?> ciResponse = sClient->/ci_builds.get(ci_build, `cicd_buildId = ${cicdId} and ci_status = "failed"`);
    var ciBuildResponse = ciResponse.next();
    while ciBuildResponse !is error? {
        json ciBuildRepsonseJson = check ciBuildResponse.value.fromJsonWithType();
        string ciBuildRecordId = check ciBuildRepsonseJson.id;
        string product = check ciBuildRepsonseJson.product;
        string version = check ciBuildRepsonseJson.version;
        json response = triggerAzureEndpoint(product, version);
        int ciRunId = check response.id;
        ci_build _ = check sClient->/ci_builds/[ciBuildRecordId].put({
            ci_status: "inProgress",
            ci_build_id: ciRunId
        });
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
    } on fail var e {
    	io:println("Error in resource function delete_failed_cd_builds.");
        io:println(e);
    }
}
