import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/uuid;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post .(customerInsert_copy[] list) returns string[]|persist:Error {
        customerInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get customer() returns customer[]|persist:Error {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, product_regular_update[]|product_hotfix_update[] product_list) returns error? {
        string UUID = uuid:createType4AsString();
        check caller->respond(UUID);
        do {
            cicd_build insertCicdbuild = check insert_cicd_build(UUID);
            ci_buildInsert[] ci_buildInsert_list = [];

            if product_list is product_regular_update[] {
                foreach product_regular_update product in product_list {
                    json response = trigger_az_endpoint(product.product_name, product.product_base_version);
                    int ci_run_id = check response.id;
                    string ci_run_state = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
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
        } on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status() returns error? { //scheduen 1
        string[] pending_ci_cicd_id_list = get_pending_ci_cicd_id_list();
        update_ci_status(pending_ci_cicd_id_list);
        update_ci_status_cicd_table(pending_ci_cicd_id_list);
    }

    isolated resource function post builds/cd/trigger() returns error? {
        string[] pending_ci_cicd_id_list = get_pending_ci_cicd_id_list();
        foreach string cicd_id in pending_ci_cicd_id_list {
            map<int> map_product_ci_id = get_map_product_ci_id(cicd_id);
            string[] product_list = map_product_ci_id.keys();
            map<string[]> map_customer_ci_list = create_map_customer_ci_list(product_list, map_product_ci_id);
            map<string> map_ci_id_state = get_map_ci_id_state(map_product_ci_id);
            foreach string customer in map_customer_ci_list.keys() {
                boolean flag = true;
                string[] build_id_list = <string[]>map_customer_ci_list[customer];
                foreach string build_id in build_id_list {
                    if "failed".equalsIgnoreCaseAscii(map_ci_id_state.get(build_id)) {
                        io:println("failed");
                        flag = false;
                        io:println(customer + " customer's CD pipline cancelled");
                        break;
                    } else if "inProgress".equalsIgnoreCaseAscii(map_ci_id_state.get(build_id)) {
                        io:println("inProgress");
                        flag = false;
                        io:println("Still building the image of customer " + customer);
                        break;
                    }
                }
                if flag {
                    update_cd_result_cicd_table(cicd_id);
                    insert_new_cd_builds(cicd_id, customer);
                }
            }
        }
    }
    isolated resource function post builds/cd/status() returns error? {
        update_inProgress_cd_builds();
    }

    isolated resource function post builds/[string cicd_id]/re\-trigger() {
        retrigger_failed_ci_builds(cicd_id);
        update_ci_cd_status_on_retrigger_ci_builds(cicd_id);
        delete_failed_cd_builds(cicd_id);
    }
}
