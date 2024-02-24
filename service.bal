import ballerina/http;
import ballerina/persist;

listener http:Listener endpoint = new (5000);

Client sClient = check initializeClient();



service /csts on endpoint {
    
    resource function post .(customerInsert[] list) returns string[]|persist:Error {
        customersInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    resource function get .() returns customers[]|persist:Error? {
        stream<customers, persist:Error?> response = sClient->/customers;
        return check from customers customer in response
           select customer;
    }

}