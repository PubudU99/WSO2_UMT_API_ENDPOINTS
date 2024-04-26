import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function get customer() returns customer[]|persist:Error {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, ProductRegularUpdate[]|ProductHotfixUpdate productUpdates) {
        do {
            string UUID = uuid:createType4AsString();
            check caller->respond(UUID);
            cicd_build insertCicdbuild = check insertCicdBuild(UUID);
            ci_buildInsert[] ciBuildInsertList = [];
            string[] productsInvolved = [];
            if productUpdates is ProductRegularUpdate[] {
                ProductRegularUpdate[] filteredProductUpdates = getFilteredProductUpdates(productUpdates);
                foreach ProductRegularUpdate product in filteredProductUpdates {
                    json response = triggerAzureEndpointCiBuild(product.productName, product.productBaseversion, "regular update");
                    int ciRunId = check response.id;
                    string ciRunState = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        ci_build_id: ciRunId,
                        ci_status: ciRunState,
                        product: product.productName,
                        version: product.productBaseversion,
                        cicd_buildId: insertCicdbuild.id,
                        update_level: "latest_test_level"
                    };
                    ciBuildInsertList.push(tmp);
                }
                productsInvolved = getProductListForInvolvedCustomerUpdateLevel(filteredProductUpdates);
            } else {
                stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(product_name = ${productUpdates.productName} AND product_base_version = ${productUpdates.productVersion}) AND customer_key = ${productUpdates.customerKey}`);
                var customerResponse = customerResponseStream.next();
                if customerResponse !is error? {
                    json customerResponseJson = check customerResponse.value.fromJsonWithType();
                    string updateLevel = check customerResponseJson.u2_level;
                    json response = triggerAzureEndpointCiBuild(productUpdates.productName, productUpdates.productVersion, "hotfix update", updateLevel);
                    int ciRunId = check response.id;
                    string ciRunState = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        ci_build_id: ciRunId,
                        ci_status: ciRunState,
                        product: productUpdates.productName,
                        version: productUpdates.productVersion,
                        cicd_buildId: insertCicdbuild.id,
                        update_level: "hotfix_update_level"
                    };
                    ciBuildInsertList.push(tmp);
                    productsInvolved = getProductListForInvolvedCustomerUpdateLevel([
                        {
                            productName: productUpdates.productName,
                            productBaseversion: productUpdates.productVersion
                        }
                    ]);
                }
            }

            string[] imagesNotInAcr = getImageNotInACR(productsInvolved);

            foreach string product in imagesNotInAcr {
                string productName = regex:split(product, "-")[0];
                string versionWithUpdatelevel = regex:split(product, "-")[1];
                versionWithUpdatelevel = regex:replaceAll(versionWithUpdatelevel, "[.]", ",");
                string productBaseversion = string:'join(".", regex:split(versionWithUpdatelevel, ",")[0], regex:split(versionWithUpdatelevel, ",")[1], regex:split(versionWithUpdatelevel, ",")[2]);
                string updateLevel = regex:split(versionWithUpdatelevel, ",")[3];
                json response = triggerAzureEndpointCiBuild(productName, productBaseversion, "regular update", updateLevel);
                int ciRunId = check response.id;
                string ciRunState = check response.state;
                ci_buildInsert tmp = {
                    id: uuid:createType4AsString(),
                    ci_build_id: ciRunId,
                    ci_status: ciRunState,
                    product: productName,
                    version: productBaseversion,
                    cicd_buildId: insertCicdbuild.id,
                    update_level: updateLevel
                };
                ciBuildInsertList.push(tmp);
            }
            string[] _ = check sClient->/ci_builds.post(ciBuildInsertList);
        }
        on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status(@http:Header string? x_authorization) returns http:Unauthorized|http:Ok {
        string accessToken = <string>x_authorization;
        if (accessToken == webhookAccessToken) {
            sql:ParameterizedQuery whereClause = `ci_result = "inProgress"`;
            string[] CiPendingCicdIdList = getCiPendingCicdIdList(whereClause);
            updateCiStatus(CiPendingCicdIdList);
            updateCiStatusCicdTable(CiPendingCicdIdList);
            return http:OK;
        } else {
            return http:UNAUTHORIZED;
        }
    }

    isolated resource function post builds/cd/trigger(@http:Header string? x_authorization) returns http:Unauthorized|http:Ok {
        string accessToken = <string>x_authorization;
        if (accessToken == webhookAccessToken) {
            sql:ParameterizedQuery whereClause = `ci_result = "inProgress" OR ci_result = "succeeded"`;
            string[] CiPendingCicdIdList = getCiPendingCicdIdList(whereClause);
            foreach string cicdId in CiPendingCicdIdList {
                map<int> mapProductCiId = getMapProductCiId(cicdId);
                string[] productList = mapProductCiId.keys();
                map<string[]> mapCustomerCiList = createMapCustomerCiList(productList, mapProductCiId);
                map<string> mapCiIdState = getMapCiIdState(mapProductCiId);
                foreach string customer in mapCustomerCiList.keys() {
                    boolean anyBuildFailed = false;
                    boolean anyBuildStillInProgress = false;
                    string[] buildIdList = <string[]>mapCustomerCiList[customer];
                    foreach string buildId in buildIdList {
                        if "failed".equalsIgnoreCaseAscii(mapCiIdState.get(buildId)) && !"inProgress".equalsIgnoreCaseAscii(mapCiIdState.get(buildId)) {
                            anyBuildFailed = true;
                            io:println(customer + " customer's CD pipline cancelled");
                            break;
                        } else if "inProgress".equalsIgnoreCaseAscii(mapCiIdState.get(buildId)) {
                            anyBuildStillInProgress = true;
                        }
                    }
                    if anyBuildFailed {
                        stream<cd_build, persist:Error?> cd_response = sClient->/cd_builds.get(cd_build, `cicd_buildId = ${cicdId} and customer = ${customer}`);
                        var cdBuildResponse = cd_response.next();
                        if cdBuildResponse is error? {
                            cd_buildInsert[] tmp = [
                                {
                                    id: uuid:createType4AsString(),
                                    cd_build_id: -1,
                                    cd_status: "failed",
                                    customer: customer,
                                    cicd_buildId: cicdId
                                }
                            ];
                            string[] _ = check sClient->/cd_builds.post(tmp);
                            updateCdResultCicdParentTable();
                        }
                    } else if !anyBuildStillInProgress {
                        updateCdResultCicdTable(cicdId);
                        insertNewCdBuilds(cicdId, customer);
                    }
                } on fail var e {
                    io:println("Error in resource function builds/cd/trigger.");
                    io:println(e);
                }
            }
            return http:OK;
        } else {
            return http:UNAUTHORIZED;
        }
    }
    isolated resource function post builds/cd/status(@http:Header string? x_authorization) returns http:Unauthorized|http:Ok {
        string accessToken = <string>x_authorization;
        if (accessToken == webhookAccessToken) {
            updateInProgressCdBuilds();
            updateCdResultCicdParentTable();
            return http:OK;
        } else {
            return http:UNAUTHORIZED;
        }
    }

    isolated resource function get builds/[string cicdId]() returns Chunkinfo|error {
        CiBuildInfo[] ciBuild = getCiBuildinfo(cicdId);
        CdBuildInfo[] cdBuild = check getCdBuildinfo(cicdId);
        Chunkinfo chunkInfo = {
            id: cicdId,
            ciBuild: ciBuild,
            cdBuild: cdBuild
        };
        return chunkInfo;
    }

    isolated resource function post builds/[string cicdId]/re\-trigger() {
        deleteFailedCdBuilds(cicdId);
        retriggerFailedCiBuilds(cicdId);
        updateCiCdStatusOnRetriggerCiBuilds(cicdId);
    }

    isolated resource function post acr\-cleanup() returns error? {
        string[] acrImageList = getImageInACR();
        string[] productImageListForCustomerupdateLevel = getProductImageForCustomerUpdateLevel();

        // create a map with boolean false
        map<boolean> acrImageListMap = {};
        foreach string imageName in acrImageList {
            acrImageListMap[imageName] = false;
        }

        // Mark the customer products images with their update level as true
        foreach string imageName in productImageListForCustomerupdateLevel {
            if acrImageListMap.hasKey(imageName) {
                acrImageListMap[imageName] = true;
            }
        }

        string[] imagesInLatestTestLevel = acrImageList.filter(image => regex:split(image, "-").length() > 2).sort("descending", isolated function(string val) returns string => re `.*-(\d)`.replace(val, "$1"));

        // Mark the last 5 images created as true
        int imageLength = imagesInLatestTestLevel.length();
        if imageLength > 5 {
            acrImageListMap[imagesInLatestTestLevel[0]] = true;
            acrImageListMap[imagesInLatestTestLevel[1]] = true;
            acrImageListMap[imagesInLatestTestLevel[2]] = true;
            acrImageListMap[imagesInLatestTestLevel[3]] = true;
            acrImageListMap[imagesInLatestTestLevel[4]] = true;
        }

        // Filter the images which are in value false that need to be deleted
        map<boolean> cleanupAcrImagelistMap = acrImageListMap.filter(image => image == false);

        // Delete the images
        foreach string image in cleanupAcrImagelistMap.keys() {
            http:Client acrEndpoint = check getAcrEndpoint();
            DeletedImage _ = check acrEndpoint->/[image].delete();
        }
    }

}
