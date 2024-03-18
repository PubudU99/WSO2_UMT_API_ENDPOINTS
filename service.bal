import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/sql;
import ballerina/uuid;
import ballerina/task;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post .(customerInsert_copy[] list) returns string[]|persist:Error {
        customerInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get customer() returns customer[]|error? {
        stream<customer, persist:Error?> response = sClient->/customers;
        var cust = response.next();
        // The `next()` will return an error if an evaluation of a query clause results in an error.
        while (cust !is error?) {
            json cust_new = check cust.value.fromJsonWithType();
            io:println(cust_new.id);
            cust = response.next();
        }
        response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    // THIS ENDPOINT NEED TO BE REMOVED FROM THE IMPLEMENTATION
    isolated resource function post filtercst(product_regular_update[] product_list) returns customer[]|persist:Error? {
        sql:ParameterizedQuery where_clause = create_where_clause(product_list);
        stream<customer, persist:Error?> response = sClient->/customers.get(customer, where_clause);
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(product_regular_update[]|product_hotfix_update[] product_list) returns string|error {
        string UUID = uuid:createType4AsString();
        cicd_build insertCicdbuild = check insert_cicd_build(UUID);
        map<int> map_product_ci_id = {}; 

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

                map_product_ci_id[string:'join("-", product.product_name, product.product_base_version)] = ci_run_id;
            }
            // string[] ci_run_id_list = check sClient->/ci_builds.post(ci_buildInsert_list);

        }

        map<int[]> map_customer_ci_id = create_customer_product_map(product_list, map_product_ci_id);

        task:JobId _ = check task:scheduleJobRecurByFrequency(new ci_run_check(map_product_ci_id, map_customer_ci_id), 10);

        return "response";
    }
}
