// AUTO-GENERATED FILE. DO NOT MODIFY.

// This file is an auto-generated file by Ballerina persistence layer for model.
// It should not be modified by hand.

public type customer record {|
    readonly string id;
    string customer_key;
    string environment;
    string product_name;
    string product_base_version;
    string u2_level;
|};

public type customerOptionalized record {|
    string id?;
    string customer_key?;
    string environment?;
    string product_name?;
    string product_base_version?;
    string u2_level?;
|};

public type customerTargetType typedesc<customerOptionalized>;

public type customerInsert customer;

public type customerUpdate record {|
    string customer_key?;
    string environment?;
    string product_name?;
    string product_base_version?;
    string u2_level?;
|};

public type cicd_build record {|
    readonly string id;
    string uuid;
|};

public type cicd_buildOptionalized record {|
    string id?;
    string uuid?;
|};

public type cicd_buildWithRelations record {|
    *cicd_buildOptionalized;
    ci_buildOptionalized[] ci_builds?;
    cd_buildOptionalized[] cd_builds?;
|};

public type cicd_buildTargetType typedesc<cicd_buildWithRelations>;

public type cicd_buildInsert cicd_build;

public type cicd_buildUpdate record {|
    string uuid?;
|};

public type ci_build record {|
    readonly string id;
    string uuid;
    int ci_build_id;
    string ci_status;
    string product;
    string version;
    string cicd_buildId;
|};

public type ci_buildOptionalized record {|
    string id?;
    string uuid?;
    int ci_build_id?;
    string ci_status?;
    string product?;
    string version?;
    string cicd_buildId?;
|};

public type ci_buildWithRelations record {|
    *ci_buildOptionalized;
    cicd_buildOptionalized cicd_build?;
|};

public type ci_buildTargetType typedesc<ci_buildWithRelations>;

public type ci_buildInsert ci_build;

public type ci_buildUpdate record {|
    string uuid?;
    int ci_build_id?;
    string ci_status?;
    string product?;
    string version?;
    string cicd_buildId?;
|};

public type cd_build record {|
    readonly string id;
    string uuid;
    string cd_build_id;
    string cd_status;
    string customer;
    string cicd_buildId;
|};

public type cd_buildOptionalized record {|
    string id?;
    string uuid?;
    string cd_build_id?;
    string cd_status?;
    string customer?;
    string cicd_buildId?;
|};

public type cd_buildWithRelations record {|
    *cd_buildOptionalized;
    cicd_buildOptionalized cicd_build?;
|};

public type cd_buildTargetType typedesc<cd_buildWithRelations>;

public type cd_buildInsert cd_build;

public type cd_buildUpdate record {|
    string uuid?;
    string cd_build_id?;
    string cd_status?;
    string customer?;
    string cicd_buildId?;
|};

