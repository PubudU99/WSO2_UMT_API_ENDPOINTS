import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

boolean unschedule_flag = false;

type customerInsert_copy record {|
    string customer_key;
    string environment;
    string product_name;
    string product_base_version;
    string u2_level;
|};

type ci_build_copy record {|
    string id;
    string ci_build_id;
    string ci_status;
    string product;
    string version;

    // many-to-one relationship with cicd_build
    cicd_build cicd_build;
|};

type product_regular_update record {|
    string product_name;
    string product_base_version;
|};

type product_hotfix_update record {|
    string product_name;
    string product_base_version;
    string u2_level;
|};

isolated function get_run_result(string run_id) returns json {
    do {
        http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
        json response = check pipelineEndpoint->/runs/[run_id].get(api\-version = "7.1-preview.1");
        return response;
    } on fail var e {
        io:println("Error in function get_run_result");
        io:println(e);
    }
}

isolated function trigger_az_endpoint(string product, string version) returns json {
    do {
        http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
        json response = check pipelineEndpoint->/runs.post({
                templateParameters: {
                    product: product,
                    version: version
                }
            },
            api\-version = "7.1-preview.1"
        );
        return response;
    } on fail var e {
        io:println("Error in function trigger_az_endpoint");
        io:println(e);
    }
}

isolated function get_map_ci_id_state(map<int> map_product_ci_id) returns map<string> {
    map<string> map_ci_id_state = {};
    foreach string product in map_product_ci_id.keys() {
        int ci_id = map_product_ci_id.get(product);
        json run = get_run_result(ci_id.toString());
        string run_state = check run.state;
        sql:ParameterizedQuery where_clause = `ci_build_id = ${ci_id}`;
        stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, where_clause);
        var ci_build_response = check response.next();
        if ci_build_response !is error? {
            json ci_build_response_json = check ci_build_response.value.fromJsonWithType();
            string ci_build_record_id = check ci_build_response_json.id;
            if run_state.equalsIgnoreCaseAscii("completed") {
                string run_result = check run.result;
                ci_build _ = check sClient->/ci_builds/[ci_build_record_id].put({
                    ci_status: run_result
                });
                map_ci_id_state[ci_id.toString()] = run_result;
            } else {
                map_ci_id_state[ci_id.toString()] = run_state;
            }
        }
    } on fail var e {
        io:println("Error in function get_map_ci_id_state");
        io:println(e);
    }
    return map_ci_id_state;
}

isolated function initializeClient() returns Client|persist:Error {
    return new Client();
}

isolated function get_customers_to_insert(customerInsert_copy[] list) returns customerInsert[] {
    customerInsert[] cst_info_list = [];

    foreach customerInsert_copy item in list {

        customerInsert tmp = {
            id: uuid:createType4AsString(),
            customer_key: item.customer_key,
            environment: item.environment,
            product_name: item.product_name,
            product_base_version: item.product_base_version,
            u2_level: item.u2_level
        };

        cst_info_list.push(tmp);
    }

    return cst_info_list;
}

isolated function create_product_where_clause(product_regular_update[] product_list) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery where_clause = ``;
    int i = 0;
    while i < product_list.length() {
        if (i == product_list.length() - 1) {
            where_clause = sql:queryConcat(where_clause, `(product_name = ${product_list[i].product_name} AND product_base_version = ${product_list[i].product_base_version})`);
        } else {
            where_clause = sql:queryConcat(where_clause, `(product_name = ${product_list[i].product_name} AND product_base_version = ${product_list[i].product_base_version}) OR `);
        }
        i += 1;
    }
    return where_clause;
}

isolated function getPipelineURL(string organization, string project, string pipeline_id) returns string {
    return "https://dev.azure.com/" + organization + "/" + project + "/_apis/pipelines/" + pipeline_id;
}

isolated function pipeline_endpoint(string pipeline_id) returns http:Client|error {
    http:Client clientEndpoint = check new (getPipelineURL(organization, project, pipeline_id), {
        auth: {
            username: "PAT_AZURE_DEVOPS",
            password: PAT_AZURE_DEVOPS
        }
    }
    );
    return clientEndpoint;
}

isolated function insert_cicd_build(string uuid) returns cicd_buildInsert|error {
    cicd_buildInsert[] cicd_buildInsert_list = [];

    cicd_buildInsert tmp = {
        id: uuid,
        ci_result: "inProgress",
        cd_result: "pending"
    };

    cicd_buildInsert_list.push(tmp);

    string[] _ = check sClient->/cicd_builds.post(cicd_buildInsert_list);

    return tmp;
}

isolated function create_map_customer_ci_list(string[] product_list, map<int> map_product_ci_id) returns map<string[]> {
    map<string[]> map_customer_product = {};
    // If the product list is type product_regular_update
    foreach string product in product_list {
        // selecting the customers whose deployment has the specific update products
        string product_name = regex:split(product, "-")[0];
        string version = regex:split(product, "-")[1];
        sql:ParameterizedQuery where_clause_product = `(product_name = ${product_name} AND product_base_version = ${version})`;
        stream<customer, persist:Error?> response = sClient->/customers.get(customer, where_clause_product);
        var customer_stream_item = response.next();
        int customer_product_ci_id = <int>map_product_ci_id[product];
        // Iterate on the customer list and maintaining a map to record which builds should be completed for a spcific customer to start tests
        while customer_stream_item !is error? {
            json customer = check customer_stream_item.value.fromJsonWithType();
            string customer_name = check customer.customer_key;
            string[] tmp;
            if map_customer_product.hasKey(customer_name) {
                tmp = map_customer_product.get(customer_name);
                tmp.push(customer_product_ci_id.toString());
            } else {
                tmp = [];
                tmp.push(customer_product_ci_id.toString());
            }
            map_customer_product[customer_name] = tmp;
            customer_stream_item = response.next();
        } on fail var e {
            io:println("Error in function create_customer_product_map");
            io:println(e);
        }
    }
    return map_customer_product;
}

isolated function get_pending_ci_cicd_id_list() returns string[] {
    sql:ParameterizedQuery where_clause = `ci_result = "pending"`;
    string[] id_list = [];
    stream<cicd_build, persist:Error?> response = sClient->/cicd_builds.get(cicd_build, where_clause);
    var id_response = response.next();
    while id_response !is error? {
        json id_record = check id_response.value.fromJsonWithType();
        string id = check id_record.id;
        id_list.push(id);
        id_response = response.next();
    } on fail var e {
        io:println("Error in function get_pending_ci_id_list ");
        io:println(e);
    }
    return id_list;
}

isolated function update_ci_status(string[] id_list) {
    do {
        http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
        sql:ParameterizedQuery where_clause = ``;
        int i = 0;
        foreach string id in id_list {
            if (i == id_list.length() - 1) {
                where_clause = sql:queryConcat(where_clause, `cicd_buildId = ${id}`);
            } else {
                where_clause = sql:queryConcat(where_clause, `cicd_buildId = ${id} OR `);
            }
            i += 1;
        }
        stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, where_clause);
        var ci_build_response = response.next();
        while ci_build_response !is error? {
            json ci_build_response_json = check ci_build_response.value.fromJsonWithType();
            int ci_build_id = check ci_build_response_json.ci_build_id;
            string ci_id = check ci_build_response_json.id;
            json run_response = check pipelineEndpoint->/runs/[ci_build_id].get(api\-version = "7.1-preview.1");
            string run_state = check run_response.state;
            string run_result;
            if ("completed".equalsIgnoreCaseAscii(run_state)) {
                run_result = check run_response.result;
            } else {
                run_result = check run_response.state;
            }
            ci_build _ = check sClient->/ci_builds/[ci_id].put({
                ci_status: run_result
            });
            ci_build_response = response.next();
        } on fail var e {
            io:println("Error in function get_id_list ");
            io:println(e);
        }
    } on fail var e {
        io:println("Error in function update_ci_status");
        io:println(e);
    }
}

isolated function update_ci_status_cicd_table(string[] id_list) {
    do {
        foreach string id in id_list {
            sql:ParameterizedQuery where_clause = `cicd_buildId = ${id}`;
            stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, where_clause);
            var ci_build_response = response.next();
            boolean all_succeeded_flag = true;
            boolean all_completed_flag = true;
            while ci_build_response !is error? {
                json ci_build_response_json = check ci_build_response.value.fromJsonWithType();
                string ci_build_status = check ci_build_response_json.ci_status;
                if (!ci_build_status.equalsIgnoreCaseAscii("succeeded") && !ci_build_status.equalsIgnoreCaseAscii("failed")) {
                    all_completed_flag = false;
                }
                if (!ci_build_status.equalsIgnoreCaseAscii("succeeded")) {
                    all_succeeded_flag = false;
                }
                ci_build_response = response.next();
            }
            if all_completed_flag {
                stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${id}`);
                var cicd_build_response = check cd_response.next();
                if cicd_build_response is error? {
                    cicd_build _ = check sClient->/cicd_builds/[id].put({
                        ci_result: "failed",
                        cd_result: "canceled"
                    });
                }
            }
            if all_succeeded_flag {
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

isolated function get_map_product_ci_id(string cicd_id) returns map<int> {
    sql:ParameterizedQuery where_clause = `cicd_buildId = ${cicd_id}`;
    stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, where_clause);
    map<int> map_product_ci_id = {};
    var ci_build_repsonse = response.next();
    while ci_build_repsonse !is error? {
        json ci_build_repsonse_json = check ci_build_repsonse.value.fromJsonWithType();
        string product_name = check ci_build_repsonse_json.product;
        string version = check ci_build_repsonse_json.version;
        int ci_build_id = check ci_build_repsonse_json.ci_build_id;
        map_product_ci_id[string:'join("-", product_name, version)] = ci_build_id;
        ci_build_repsonse = response.next();
    } on fail var e {
        io:println("Error in function get_map_product_ci_id");
        io:println(e);
    }
    return map_product_ci_id;
}

isolated function update_cd_result_cicd_table(string cicd_id) {
    do {
        stream<cicd_build, persist:Error?> cicd_response = sClient->/cicd_builds.get(cicd_build, `id = ${cicd_id} and cd_result = "pending"`);
        var cicd_build_response = check cicd_response.next();
        if cicd_build_response !is error? {
            cicd_build _ = check sClient->/cicd_builds/[cicd_id].put({
                cd_result: "inProgress"
            });
        }
    } on fail var e {
        io:println("Error is function update_cd_result_cicd_table");
        io:println(e);
    }
}

isolated function insert_new_cd_builds(string cicd_id, string customer) {
    stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicd_id} and customer = ${customer}`);
    var cd_build_response = cd_response.next();
    if cd_build_response is error? {
        cd_buildInsert[] tmp = [
            {
                id: uuid:createType4AsString(),
                cd_build_id: "",
                cd_status: "inProgress",
                customer: customer,
                cicd_buildId: cicd_id
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

isolated function update_inProgress_cd_builds() {
    stream<cd_build, persist:Error?> response = sClient->/cd_builds.get(cd_build, `cd_status = "inProgress"`);
    var cd_build_stream_item = response.next();
    while cd_build_stream_item !is error? {
        json cd_build_stream_item_json = check cd_build_stream_item.value.fromJsonWithType();
        string cd_build_id = check cd_build_stream_item_json.cd_build_id;
        string cd_build_record_id = check cd_build_stream_item_json.id;
        json run = get_run_result(cd_build_id);
        string run_state = check run.state;
        if run_state.equalsIgnoreCaseAscii("completed") {
            string run_result = check run.result;
            ci_build _ = check sClient->/ci_builds/[cd_build_record_id].put({
                ci_status: run_result
            });
        }
    } on fail var e {
        io:println("Error is function update_inProgress_cd_builds");
        io:println(e);
    }
}

isolated function retrigger_failed_ci_builds(string cicd_id) {
    stream<ci_build, persist:Error?> ci_response = sClient->/ci_builds.get(ci_build, `cicd_buildId = ${cicd_id} and ci_status = "failed"`);
    var ci_build_response = ci_response.next();
    while ci_build_response !is error? {
        json ci_build_repsonse_json = check ci_build_response.value.fromJsonWithType();
        string ci_build_record_id = check ci_build_repsonse_json.id;
        string product = check ci_build_repsonse_json.product;
        string version = check ci_build_repsonse_json.version;
        json response = trigger_az_endpoint(product, version);
        int ci_run_id = check response.id;
        ci_build _ = check sClient->/ci_builds/[ci_build_record_id].put({
            ci_status: "inProgress",
            ci_build_id: ci_run_id
        });
    } on fail var e {
        io:println("Error in resource function retrigger_failed_ci_builds.");
        io:println(e);
    }
}

isolated function update_ci_cd_status_on_retrigger_ci_builds(string cicd_id) {
    stream<cicd_build, persist:Error?> cicd_response = sClient->/cicd_builds.get(cicd_build, `id = ${cicd_id}`);
    var cicd_build_response = cicd_response.next();
    while cicd_build_response !is error? {
        cicd_build _ = check sClient->/cicd_builds/[cicd_id].put({
            ci_result: "inProgress",
            cd_result: "pending"
        });
    } on fail var e {
        io:println("Error in resource function update_ci_cd_status_on_retrigger_ci_builds.");
        io:println(e);
    }

}

isolated function delete_failed_cd_builds(string cicd_id) {
    stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicd_id} and cd_status = "failed"`);
    var cd_build_response = cd_response.next();
    while cd_build_response !is error? {
        json cd_build_repsonse_json = check cd_build_response.value.fromJsonWithType();
        string cd_build_record_id = check cd_build_repsonse_json.id;
        cd_build _ = check sClient->/cd_builds/[cd_build_record_id].delete;
    } on fail var e {
    	io:println("Error in resource function delete_failed_cd_builds.");
        io:println(e);
    }
}
