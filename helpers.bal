import ballerina/persist;
import ballerina/uuid;
import ballerina/sql;

type customerInsert record {|
    string customer_key;
    string product_name;
    string product_base_version;
|};

type product record {|
    string product_name;
    string product_base_version;
|};

isolated function initializeClient() returns Client|persist:Error {
    return new Client();
} 

isolated function get_customers_to_insert(customerInsert[] list) returns customersInsert[]{
    customersInsert[] cst_info_list = [];

        foreach customerInsert item in list {
        
            customersInsert tmp = {
                id: uuid:createType4AsString(),
                customer_key: item.customer_key, 
                product_name: item.product_name, 
                product_base_version: item.product_base_version};

            cst_info_list.push(tmp);
        }

    return cst_info_list;
}

isolated function create_where_clause(product[] product_list) returns sql:ParameterizedQuery{
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
    return where_clause;
}