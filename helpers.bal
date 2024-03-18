import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/sql;
import ballerina/task;
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
    string uuid;
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

class ci_run_check {

    *task:Job;
    map<int> map_product_ci_id;
    map<int[]> map_customer_ci_id;
    map<boolean> map_customer_ci_result;

    public function execute() {
        foreach string customer in self.map_customer_ci_id.keys() {
            self.map_customer_ci_result[customer] = false;
        }
        map<string> map_ci_id_state = updated_map_ci_id_state(self.map_product_ci_id.length());
        foreach string customer in self.map_customer_ci_id.keys() {
            boolean flag = true;
            int[] build_id_list = <int[]>self.map_customer_ci_id[customer];
            foreach int build_id in build_id_list {
                json run = check get_run_result(build_id.toString());
                string product = check run.templateParameters.product;
                string version = check run.templateParameters.version;
                string image_name = string:'join("-", product, version);
                if ("completed".equalsIgnoreCaseAscii(map_ci_id_state[build_id.toString()] ?: "")) {
                    string run_result = check run.result;
                    if (!run_result.equalsIgnoreCaseAscii("succeeded")) {
                        self.map_customer_ci_result[customer] = true;
                        flag = false;
                        io:println("The image " + image_name + " failed of customer " + customer);
                        io:println(customer + " customer's CD pipline cancelled");
                        break;
                    }
                } else {
                    flag = false;
                    io:println("Still building the image " + image_name + " of customer " + customer);
                    break;
                }
            } on fail var e {
                io:println("Error in function execute");
                io:println(e);
            }
            if (flag) {
                self.map_customer_ci_result[customer] = true;
                io:println("Start CD pipeline of customer " + customer);
            }
        }

        unschedule_flag = self.map_customer_ci_result.reduce(function(boolean acc, boolean value) returns boolean {
            return acc && value;
        }, true);
    }

    public isolated function init(map<int> map_product_ci_id, map<int[]> map_customer_ci_id, map<boolean> map_customer_ci_result) {
        self.map_product_ci_id = map_product_ci_id;
        self.map_customer_ci_id = map_customer_ci_id;
        self.map_customer_ci_result = map_customer_ci_result;
    }

}

isolated function get_run_result(string run_id) returns json|error {
    http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
    json response = check pipelineEndpoint->/runs/[run_id].get(api\-version = "7.1-preview.1");
    return response;
}

isolated function get_build_status(string pipeline_id) returns json|error {
    http:Client pipelineEndpoint = check pipeline_endpoint(pipeline_id);

    json response = check pipelineEndpoint->/runs.get(
        api\-version = "7.1-preview.1"
    );

    return response.value;
}

isolated function updated_map_ci_id_state(int product_list_length) returns map<string> {
    map<string> ci_map = {};
    do {
        json all_build_status = check get_build_status(ci_pipeline_id);
        json[] all_build_status_json_arr = check all_build_status.fromJsonWithType();
        json[] ci_build_status_list = all_build_status_json_arr.slice(0, product_list_length).reverse();
        foreach json ci_build_status in ci_build_status_list {
            int run_id = check ci_build_status.id;
            ci_map[run_id.toString()] = check ci_build_status.state;
        }
    } on fail var e {
        io:println("Error in fucntion updated_ci_map");
        io:println(e);
    }
    return ci_map;
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

isolated function create_where_clause(product_regular_update[] product_list) returns sql:ParameterizedQuery {
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

isolated function insert_cicd_build(string UUID) returns cicd_buildInsert|error {
    cicd_buildInsert[] cicd_buildInsert_list = [];

    cicd_buildInsert tmp = {
        id: uuid:createType4AsString(),
        uuid: UUID,
        ci_result: "pending",
        cd_result: "pending"
    };

    cicd_buildInsert_list.push(tmp);

    string[] _ = check sClient->/cicd_builds.post(cicd_buildInsert_list);

    return tmp;
}

// isolated function create_customer_product_map(product_hotfix_update[]|product_regular_update[] product_list, map<int> map_product_ci_id) returns map<int[]> {
//     map<int[]> map_customer_product = {};
//     // If the product list is type product_regular_update
//     if product_list is product_regular_update[] {
//         foreach product_regular_update product in product_list {
//             // selecting the customers whose deployment has the specific update products
//             sql:ParameterizedQuery where_clause_product = `(product_name = ${product.product_name} AND product_base_version = ${product.product_base_version})`;
//             stream<customer, persist:Error?> response = sClient->/customers.get(customer, where_clause_product);
//             var customer_stream_item = response.next();
//             int customer_product_ci_id = <int>map_product_ci_id[string:'join("-", product.product_name, product.product_base_version)];
//             // Iterate on the customer list and maintaining a map to record which builds should be completed for a spcific customer to start tests
//             while customer_stream_item !is error? {
//                 json customer = check customer_stream_item.value.fromJsonWithType();
//                 string customer_name = check customer.customer_key;
//                 int[] tmp;
//                 if map_customer_product.hasKey(customer_name) {
//                     tmp = <int[]>map_customer_product[customer_name];
//                     tmp.push(customer_product_ci_id);
//                 } else {
//                     tmp = [];
//                     tmp.push(customer_product_ci_id);
//                 }
//                 map_customer_product[customer_name] = tmp;
//                 customer_stream_item = response.next();
//             } on fail var e {
//                 io:println("Error in function create_customer_product_map");
//                 io:println(e);
//             }
//         }
//         io:println(map_customer_product);
//     }
//     return map_customer_product;
// }

isolated function get_pending_ci_uuid_list() returns string[] {
    sql:ParameterizedQuery where_clause = `ci_result = "pending"`;
    string[] uuid_list = [];
    stream<customer, persist:Error?> response = sClient->/customers.get(customer, where_clause);
    var uuid_response = response.next();
    while uuid_response !is error? {
        json uuid_record = check uuid_response.value.fromJsonWithType();
        string uuid = check uuid_record.uuid;
        uuid_list.push(uuid);
        uuid_response = response.next();
    } on fail var e {
        io:println("Error in function get_uuid_list ");
        io:println(e);
    }
    return uuid_list;
}

isolated function update_ci_status(string[] uuid_list) {
    do {
        http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
        sql:ParameterizedQuery where_clause = ``;
        int i = 0;
        foreach string uuid in uuid_list {
            if (i == uuid_list.length() - 1) {
                where_clause = sql:queryConcat(where_clause, `uuid = ${uuid}`);
            } else {
                where_clause = sql:queryConcat(where_clause, `uuid = ${uuid} OR `);
            }
            i += 1;
        }
        stream<ci_build, persist:Error?> response = sClient->/ci_builds.get(ci_build, where_clause);
        var ci_build_response = response.next();
        while ci_build_response !is error? {
            json ci_build_response_json = check ci_build_response.value.fromJsonWithType();
            string ci_build_id = check ci_build_response_json.ci_build_id;
            string ci_id = check ci_build_response_json.id;
            json run_response = check pipelineEndpoint->/runs/[ci_build_id].get(api\-version = "7.1-preview.1");
            string run_state = check run_response.state;
            string run_result;
            if ("completed".equalsIgnoreCaseAscii(run_state)) {
                run_result = check run_response.result;
            } else {
                run_result = check run_response.state;
            }
            ci_buildUpdate tmp = {
                ci_status: run_result
            };
            ci_build _ = check sClient->/ci_builds/[ci_id].put(tmp);
            ci_build_response = response.next();
        } on fail var e {
            io:println("Error in function get_uuid_list ");
            io:println(e);
        }
    } on fail var e {
        io:println("Error in function update_ci_status");
        io:println(e);
    }
}