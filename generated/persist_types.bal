// AUTO-GENERATED FILE. DO NOT MODIFY.

// This file is an auto-generated file by Ballerina persistence layer for model.
// It should not be modified by hand.

public type customers record {|
    readonly string id;
    string customer_key;
    string product_name;
    string product_base_version;
|};

public type customersOptionalized record {|
    string id?;
    string customer_key?;
    string product_name?;
    string product_base_version?;
|};

public type customersTargetType typedesc<customersOptionalized>;

public type customersInsert customers;

public type customersUpdate record {|
    string customer_key?;
    string product_name?;
    string product_base_version?;
|};

