import ballerina/persist;
import ballerina/uuid;

type customerInsert record {|
    string customer_key;
    string product_name;
    string product_base_version;
|};

isolated function initializeClient() returns Client|persist:Error {
    return new Client();
} 


function get_customers_to_insert(customerInsert[] list) returns customersInsert[]{
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