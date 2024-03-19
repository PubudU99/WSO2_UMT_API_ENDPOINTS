import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/uuid;
import ballerina/lang.runtime;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post .(customerInsert_copy[] list) returns string[]|persist:Error {
        customerInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get customer() returns customer[]|error? {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, product_regular_update[]|product_hotfix_update[] product_list) returns error? {
        string UUID = uuid:createType4AsString();
        check caller->respond(UUID);
        do {
            cicd_build insertCicdbuild = check insert_cicd_build(UUID);
            http:Client pipelineEndpoint = check pipeline_endpoint(ci_pipeline_id);
            ci_buildInsert[] ci_buildInsert_list = [];

            if product_list is product_regular_update[] {
                foreach product_regular_update product in product_list {
                    json response = check pipelineEndpoint->/runs.post({
                            templateParameters: {
                                product: product.product_name,
                                version: product.product_base_version
                            }
                        },
                        api\-version = "7.1-preview.1"
                    );
                    int ci_run_id = check response.id;
                    string ci_run_state = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        uuid: UUID,
                        ci_build_id: ci_run_id,
                        ci_status: ci_run_state,
                        product: product.product_name,
                        version: product.product_base_version,
                        cicd_buildId: insertCicdbuild.id
                    };
                    ci_buildInsert_list.push(tmp);
                }
                string[] _ = check sClient->/ci_builds.post(ci_buildInsert_list);
            }

            while true {
                io:println("Schedule running");
                schedule_ci();
                trigger_cd();
                runtime:sleep(3);
            }
        } on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status() returns error? {
        string[] uuid_list = get_pending_ci_uuid_list();
        update_ci_status(uuid_list);
        update_parent_ci_status(uuid_list);
    }

    isolated resource function post builds/trigger\-cd() returns error? {
        string[] uuid_list = get_pending_ci_uuid_list();
        foreach string uuid in uuid_list {
            map<int> map_product_ci_id = get_map_product_ci_id(uuid);
            string[] product_list = map_product_ci_id.keys();
            map<string[]> map_customer_ci_list = create_map_customer_ci_list(product_list, map_product_ci_id);
            map<string> map_ci_id_state = get_map_ci_id_state(map_product_ci_id);
            foreach string customer in map_customer_ci_list.keys() {
                boolean flag = true;
                string[] build_id_list = <string[]>map_customer_ci_list[customer];
                foreach string build_id in build_id_list {
                    if "failed".equalsIgnoreCaseAscii(<string>map_ci_id_state[build_id]) {
                        flag = false;
                        // io:println("The image " + image_name + " failed of customer " + customer);
                        io:println(customer + " customer's CD pipline cancelled");
                        break;
                    } else if "inProgress".equalsIgnoreCaseAscii(<string>map_ci_id_state[build_id]) {
                        flag = false;
                        io:println("Still building the image of customer " + customer);
                        break;
                    }
                }
                if flag {
                    stream<cicd_build, persist:Error?> cicd_response = sClient->/cicd_builds.get(cicd_build, `uuid = ${uuid}`);
                    var cicd_build_response = check cicd_response.next();
                    if cicd_build_response !is error? {
                        json cicd_build_response_json = check cicd_build_response.value.fromJsonWithType();
                        string cicd_id = check cicd_build_response_json.id;
                        cicd_build _ = check sClient->/cicd_builds/[cicd_id].put({
                            cd_result: "started"
                        });
                    }
                    io:println("Start CD pipeline of customer " + customer);
                    io:println("Create an entry in cd_build table");
                }
            }
        }
    }
    isolated resource function post builds/cd/status() {
    }
}

