import ballerina/persist as _;

public type customers record {|
    readonly string id;
    string customer_key;
    string product_name;
    string product_base_version;
|};

