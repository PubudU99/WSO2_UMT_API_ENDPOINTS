import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/uuid;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post .(CustomerInsertCopy[] list) returns string[]|persist:Error {
        customerInsert[] cst_info_list = getCustomersToInsert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get customer() returns customer[]|persist:Error {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, ProductRegularUpdate[]|ProductHotfixUpdate product_updates) returns error? {
        string UUID = uuid:createType4AsString();
        check caller->respond(UUID);
        do {
            cicd_build insertCicdbuild = check insertCicdBuild(UUID);
            ci_buildInsert[] ci_buildInsert_list = [];

            if product_updates is ProductRegularUpdate[] {
                foreach ProductRegularUpdate product in product_updates {
                    json response = triggerAzureEndpoint(product.productName, product.productBaseversion);
                    int ci_run_id = check response.id;
                    string ci_run_state = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        ci_build_id: ci_run_id,
                        ci_status: ci_run_state,
                        product: product.productName,
                        version: product.productBaseversion,
                        cicd_buildId: insertCicdbuild.id
                    };
                    ci_buildInsert_list.push(tmp);
                }
                string[] _ = check sClient->/ci_builds.post(ci_buildInsert_list);
            } else {
                // json response = trigger_az_endpoint(product_updates.product_name, product_updates.product_base_version, product_updates.u2_level);
                // int ci_run_id = check response.id;
                // string ci_run_state = check response.state;
                // ci_buildInsert tmp = {
                //     id: uuid:createType4AsString(),
                //     ci_build_id: ci_run_id,
                //     ci_status: ci_run_state,
                //     product: product_updates.product_name,
                //     version: product_updates.product_base_version,
                //     cicd_buildId: insertCicdbuild.id
                // };
            }
        } on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status() returns error? { //scheduen 1
        string[] pending_ci_cicd_id_list = getCiPendingCicdIdList();
        updateCiStatus(pending_ci_cicd_id_list);
        updateCiStatusCicdTable(pending_ci_cicd_id_list);
    }

    isolated resource function post builds/cd/trigger() returns error? {
        string[] pending_ci_cicd_id_list = getCiPendingCicdIdList();
        foreach string cicd_id in pending_ci_cicd_id_list {
            map<int> map_product_ci_id = getMapProductCiId(cicd_id);
            string[] product_list = map_product_ci_id.keys();
            map<string[]> map_customer_ci_list = createMapCustomerCiList(product_list, map_product_ci_id);
            map<string> map_ci_id_state = getMapCiIdState(map_product_ci_id);
            foreach string customer in map_customer_ci_list.keys() {
                boolean flag = true;
                string[] build_id_list = <string[]>map_customer_ci_list[customer];
                foreach string build_id in build_id_list {
                    if "failed".equalsIgnoreCaseAscii(map_ci_id_state.get(build_id)) {
                        flag = false;
                        io:println(customer + " customer's CD pipline cancelled");
                        break;
                    } else if "inProgress".equalsIgnoreCaseAscii(map_ci_id_state.get(build_id)) {
                        flag = false;
                        io:println("Still building the image of customer " + customer);
                        break;
                    }
                }
                if flag {
                    updateCdResultCicdTable(cicd_id);
                    insertNewCdBuilds(cicd_id, customer);
                }
            }
        }
    }
    isolated resource function post builds/cd/status() returns error? {
        updateInProgressCdBuilds();
    }

    isolated resource function post builds/[string cicd_id]/re\-trigger() {
        retriggerFailedCiBuilds(cicd_id);
        updateCiCdStatusOnRetriggerCiBuilds(cicd_id);
        deleteFailedCdBuilds(cicd_id);
    }
}
