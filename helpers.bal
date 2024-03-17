import ballerina/http;
import ballerina/persist;
import ballerina/sql;
import ballerina/uuid;
import ballerina/io;

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

isolated function pipeline_endpoint() returns http:Client|error {
    http:Client clientEndpoint = check new ("https://dev.azure.com/" + organization + "/" + project + "/_apis/pipelines/" + pipeline_id, {
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
        uuid: UUID
    };

    cicd_buildInsert_list.push(tmp);

    string[] cicd_buildId = check sClient->/cicd_builds.post(cicd_buildInsert_list);

    io:println("cicd_buildId = " + cicd_buildId[0]);

    return tmp;
}
