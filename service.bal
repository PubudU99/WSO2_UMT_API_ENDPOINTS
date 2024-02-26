import ballerina/http;
import ballerina/persist;
import ballerina/sql;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {
    
    isolated resource function post .(customerInsert[] list) returns string[]|persist:Error {
        customersInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get all() returns customers[]|persist:Error? {
        stream<customers, persist:Error?> response = sClient->/customers;
        return check from customers customer in response
           select customer;
    }

    isolated resource function post filtercst(product[] product_list) returns customers[]|persist:Error? {
        sql:ParameterizedQuery where_clause = create_where_clause(product_list);
        stream<customers, persist:Error?> response = sClient->/customers.get(customers, where_clause);
        return check from customers customer in response
           select customer;
    }

}