// AUTO-GENERATED FILE. DO NOT MODIFY.
// This file is an auto-generated file by Ballerina persistence layer for model.
// It should not be modified by hand.
import ballerina/jballerina.java;
import ballerina/persist;
import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;
import ballerinax/persist.sql as psql;

const CUSTOMER = "customers";
const CICD_BUILD = "cicd_builds";
const CI_BUILD = "ci_builds";
const CD_BUILD = "cd_builds";

public isolated client class Client {
    *persist:AbstractPersistClient;

    private final mysql:Client dbClient;

    private final map<psql:SQLClient> persistClients;

    private final record {|psql:SQLMetadata...;|} & readonly metadata = {
        [CUSTOMER] : {
            entityName: "customer",
            tableName: "customer",
            fieldMetadata: {
                id: {columnName: "id"},
                customer_key: {columnName: "customer_key"},
                environment: {columnName: "environment"},
                product_name: {columnName: "product_name"},
                product_base_version: {columnName: "product_base_version"},
                u2_level: {columnName: "u2_level"}
            },
            keyFields: ["id"]
        },
        [CICD_BUILD] : {
            entityName: "cicd_build",
            tableName: "cicd_build",
            fieldMetadata: {
                id: {columnName: "id"},
                ci_result: {columnName: "ci_result"},
                cd_result: {columnName: "cd_result"},
                event_timestamp: {columnName: "event_timestamp"},
                "ci_builds[].id": {relation: {entityName: "ci_builds", refField: "id"}},
                "ci_builds[].ci_build_id": {relation: {entityName: "ci_builds", refField: "ci_build_id"}},
                "ci_builds[].ci_status": {relation: {entityName: "ci_builds", refField: "ci_status"}},
                "ci_builds[].product": {relation: {entityName: "ci_builds", refField: "product"}},
                "ci_builds[].version": {relation: {entityName: "ci_builds", refField: "version"}},
                "ci_builds[].update_level": {relation: {entityName: "ci_builds", refField: "update_level"}},
                "ci_builds[].event_timestamp": {relation: {entityName: "ci_builds", refField: "event_timestamp"}},
                "ci_builds[].cicd_buildId": {relation: {entityName: "ci_builds", refField: "cicd_buildId"}},
                "cd_builds[].id": {relation: {entityName: "cd_builds", refField: "id"}},
                "cd_builds[].cd_build_id": {relation: {entityName: "cd_builds", refField: "cd_build_id"}},
                "cd_builds[].cd_status": {relation: {entityName: "cd_builds", refField: "cd_status"}},
                "cd_builds[].customer": {relation: {entityName: "cd_builds", refField: "customer"}},
                "cd_builds[].event_timestamp": {relation: {entityName: "cd_builds", refField: "event_timestamp"}},
                "cd_builds[].cicd_buildId": {relation: {entityName: "cd_builds", refField: "cicd_buildId"}}
            },
            keyFields: ["id"],
            joinMetadata: {
                ci_builds: {entity: ci_build, fieldName: "ci_builds", refTable: "ci_build", refColumns: ["cicd_buildId"], joinColumns: ["id"], 'type: psql:MANY_TO_ONE},
                cd_builds: {entity: cd_build, fieldName: "cd_builds", refTable: "cd_build", refColumns: ["cicd_buildId"], joinColumns: ["id"], 'type: psql:MANY_TO_ONE}
            }
        },
        [CI_BUILD] : {
            entityName: "ci_build",
            tableName: "ci_build",
            fieldMetadata: {
                id: {columnName: "id"},
                ci_build_id: {columnName: "ci_build_id"},
                ci_status: {columnName: "ci_status"},
                product: {columnName: "product"},
                version: {columnName: "version"},
                update_level: {columnName: "update_level"},
                event_timestamp: {columnName: "event_timestamp"},
                cicd_buildId: {columnName: "cicd_buildId"},
                "cicd_build.id": {relation: {entityName: "cicd_build", refField: "id"}},
                "cicd_build.ci_result": {relation: {entityName: "cicd_build", refField: "ci_result"}},
                "cicd_build.cd_result": {relation: {entityName: "cicd_build", refField: "cd_result"}},
                "cicd_build.event_timestamp": {relation: {entityName: "cicd_build", refField: "event_timestamp"}}
            },
            keyFields: ["id"],
            joinMetadata: {cicd_build: {entity: cicd_build, fieldName: "cicd_build", refTable: "cicd_build", refColumns: ["id"], joinColumns: ["cicd_buildId"], 'type: psql:ONE_TO_MANY}}
        },
        [CD_BUILD] : {
            entityName: "cd_build",
            tableName: "cd_build",
            fieldMetadata: {
                id: {columnName: "id"},
                cd_build_id: {columnName: "cd_build_id"},
                cd_status: {columnName: "cd_status"},
                customer: {columnName: "customer"},
                event_timestamp: {columnName: "event_timestamp"},
                cicd_buildId: {columnName: "cicd_buildId"},
                "cicd_build.id": {relation: {entityName: "cicd_build", refField: "id"}},
                "cicd_build.ci_result": {relation: {entityName: "cicd_build", refField: "ci_result"}},
                "cicd_build.cd_result": {relation: {entityName: "cicd_build", refField: "cd_result"}},
                "cicd_build.event_timestamp": {relation: {entityName: "cicd_build", refField: "event_timestamp"}}
            },
            keyFields: ["id"],
            joinMetadata: {cicd_build: {entity: cicd_build, fieldName: "cicd_build", refTable: "cicd_build", refColumns: ["id"], joinColumns: ["cicd_buildId"], 'type: psql:ONE_TO_MANY}}
        }
    };

    public isolated function init() returns persist:Error? {
        mysql:Client|error dbClient = new (host = host, user = user, password = password, database = database, port = port, options = connectionOptions, connectionPool =connectionPool);
        if dbClient is error {
            return <persist:Error>error(dbClient.message());
        }
        self.dbClient = dbClient;
        self.persistClients = {
            [CUSTOMER] : check new (dbClient, self.metadata.get(CUSTOMER), psql:MYSQL_SPECIFICS),
            [CICD_BUILD] : check new (dbClient, self.metadata.get(CICD_BUILD), psql:MYSQL_SPECIFICS),
            [CI_BUILD] : check new (dbClient, self.metadata.get(CI_BUILD), psql:MYSQL_SPECIFICS),
            [CD_BUILD] : check new (dbClient, self.metadata.get(CD_BUILD), psql:MYSQL_SPECIFICS)
        };
    }

    isolated resource function get customers(customerTargetType targetType = <>, sql:ParameterizedQuery whereClause = ``, sql:ParameterizedQuery orderByClause = ``, sql:ParameterizedQuery limitClause = ``, sql:ParameterizedQuery groupByClause = ``) returns stream<targetType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "query"
    } external;

    isolated resource function get customers/[int id](customerTargetType targetType = <>) returns targetType|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "queryOne"
    } external;

    isolated resource function post customers(customerInsert[] data) returns int[]|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CUSTOMER);
        }
        _ = check sqlClient.runBatchInsertQuery(data);
        return from customerInsert inserted in data
            select inserted.id;
    }

    isolated resource function put customers/[int id](customerUpdate value) returns customer|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CUSTOMER);
        }
        _ = check sqlClient.runUpdateQuery(id, value);
        return self->/customers/[id].get();
    }

    isolated resource function delete customers/[int id]() returns customer|persist:Error {
        customer result = check self->/customers/[id].get();
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CUSTOMER);
        }
        _ = check sqlClient.runDeleteQuery(id);
        return result;
    }

    isolated resource function get cicd_builds(cicd_buildTargetType targetType = <>, sql:ParameterizedQuery whereClause = ``, sql:ParameterizedQuery orderByClause = ``, sql:ParameterizedQuery limitClause = ``, sql:ParameterizedQuery groupByClause = ``) returns stream<targetType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "query"
    } external;

    isolated resource function get cicd_builds/[string id](cicd_buildTargetType targetType = <>) returns targetType|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "queryOne"
    } external;

    isolated resource function post cicd_builds(cicd_buildInsert[] data) returns string[]|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CICD_BUILD);
        }
        _ = check sqlClient.runBatchInsertQuery(data);
        return from cicd_buildInsert inserted in data
            select inserted.id;
    }

    isolated resource function put cicd_builds/[string id](cicd_buildUpdate value) returns cicd_build|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CICD_BUILD);
        }
        _ = check sqlClient.runUpdateQuery(id, value);
        return self->/cicd_builds/[id].get();
    }

    isolated resource function delete cicd_builds/[string id]() returns cicd_build|persist:Error {
        cicd_build result = check self->/cicd_builds/[id].get();
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CICD_BUILD);
        }
        _ = check sqlClient.runDeleteQuery(id);
        return result;
    }

    isolated resource function get ci_builds(ci_buildTargetType targetType = <>, sql:ParameterizedQuery whereClause = ``, sql:ParameterizedQuery orderByClause = ``, sql:ParameterizedQuery limitClause = ``, sql:ParameterizedQuery groupByClause = ``) returns stream<targetType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "query"
    } external;

    isolated resource function get ci_builds/[int id](ci_buildTargetType targetType = <>) returns targetType|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "queryOne"
    } external;

    isolated resource function post ci_builds(ci_buildInsert[] data) returns int[]|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CI_BUILD);
        }
        _ = check sqlClient.runBatchInsertQuery(data);
        return from ci_buildInsert inserted in data
            select inserted.id;
    }

    isolated resource function put ci_builds/[int id](ci_buildUpdate value) returns ci_build|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CI_BUILD);
        }
        _ = check sqlClient.runUpdateQuery(id, value);
        return self->/ci_builds/[id].get();
    }

    isolated resource function delete ci_builds/[int id]() returns ci_build|persist:Error {
        ci_build result = check self->/ci_builds/[id].get();
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CI_BUILD);
        }
        _ = check sqlClient.runDeleteQuery(id);
        return result;
    }

    isolated resource function get cd_builds(cd_buildTargetType targetType = <>, sql:ParameterizedQuery whereClause = ``, sql:ParameterizedQuery orderByClause = ``, sql:ParameterizedQuery limitClause = ``, sql:ParameterizedQuery groupByClause = ``) returns stream<targetType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "query"
    } external;

    isolated resource function get cd_builds/[int id](cd_buildTargetType targetType = <>) returns targetType|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "queryOne"
    } external;

    isolated resource function post cd_builds(cd_buildInsert[] data) returns int[]|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CD_BUILD);
        }
        _ = check sqlClient.runBatchInsertQuery(data);
        return from cd_buildInsert inserted in data
            select inserted.id;
    }

    isolated resource function put cd_builds/[int id](cd_buildUpdate value) returns cd_build|persist:Error {
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CD_BUILD);
        }
        _ = check sqlClient.runUpdateQuery(id, value);
        return self->/cd_builds/[id].get();
    }

    isolated resource function delete cd_builds/[int id]() returns cd_build|persist:Error {
        cd_build result = check self->/cd_builds/[id].get();
        psql:SQLClient sqlClient;
        lock {
            sqlClient = self.persistClients.get(CD_BUILD);
        }
        _ = check sqlClient.runDeleteQuery(id);
        return result;
    }

    remote isolated function queryNativeSQL(sql:ParameterizedQuery sqlQuery, typedesc<record {}> rowType = <>) returns stream<rowType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor"
    } external;

    remote isolated function executeNativeSQL(sql:ParameterizedQuery sqlQuery) returns psql:ExecutionResult|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor"
    } external;

    public isolated function close() returns persist:Error? {
        error? result = self.dbClient.close();
        if result is error {
            return <persist:Error>error(result.message());
        }
        return result;
    }
}

