import ballerina/http;
import ballerina/persist;
import ballerina/sql;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

type product record {|
    string product_name;
    string product_base_version;
|};

service /csts on endpoint {
    
    isolated resource function post .(customerInsert[] list) returns string[]|persist:Error {
        customersInsert[] cst_info_list = get_customers_to_insert(list);
        return sClient->/customers.post(cst_info_list);
    }

    isolated resource function get all() returns customers[]|persist:Error? {
        stream<customers, persist:Error?> response = sClient->/customers;
        return check from customers customer in response
           select customer;
    }

    isolated resource function post findcst(product[] product_list) returns customers[]|persist:Error? {
        sql:ParameterizedQuery where_clause = ``;
        int i= 0;
        while i < product_list.length() {
            if(i == product_list.length() - 1){
                where_clause = sql:queryConcat(where_clause, `(product_name = ${product_list[i].product_name} AND product_base_version = ${product_list[i].product_base_version})`);
            } else {
                where_clause = sql:queryConcat(where_clause, `(product_name = ${product_list[i].product_name} AND product_base_version = ${product_list[i].product_base_version}) OR `);
            }
            i += 1;
        }
        stream<customers, persist:Error?> response = sClient->/customers.get(customers, where_clause);
        return check from customers customer in response
           select customer;
        // return where_clause;
    }

}