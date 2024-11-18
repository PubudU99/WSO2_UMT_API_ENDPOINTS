import ballerina/http;        //no
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post customer(CustomerInsertCopy[] list) returns error? {
        foreach CustomerInsertCopy customer in list {
            _ = check sClient->executeNativeSQL(`
                INSERT INTO customer (customer_key, environment, product_name, product_base_version, u2_level)
                VALUES (${customer.customerKey}, ${customer.environment}, ${customer.productName}, ${customer.productBaseversion}, ${customer.u2Level});`);
        }
    }

    isolated resource function get customer() returns customer[]|persist:Error {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, ProductRegularUpdate[]|ProductHotfixUpdate productUpdates) {
        do {
            string UUID = uuid:createType4AsString();
            ciBuildInsertCopy[] ciBuildInsertList = [];
            string[] productsInvolved = [];
            if productUpdates is ProductRegularUpdate[] {
                ProductRegularUpdate[] filteredProductUpdates = getFilteredProductUpdates(productUpdates);
                if filteredProductUpdates.length() == 0 {
                    json UMTResponse = {
                        uuid:"",
                        Reason:"No CST Available"  
                    };
                    check caller->respond(UMTResponse);
                }
                else {
                    json UMTResponse = {
                        uuid:UUID,
                        Reason:"CST Available"  
                    };
                    check caller->respond(UMTResponse));
                    check insertCicdBuild(UUID);
                    foreach ProductRegularUpdate product in filteredProductUpdates {
                        json response = triggerAzureEndpointCiBuild(product.productName, product.productBaseversion, "regular update");
                        int ciRunId = check response.id;
                        string ciRunState = check response.state;
                        ciBuildInsertCopy tmp = {
                            ciBuildId: ciRunId,
                            ciStatus: ciRunState,
                            product: product.productName,
                            version: product.productBaseversion,
                            cicdBuildId: UUID,
                            updateLevel: "latest_test_level"
                        };
                        ciBuildInsertList.push(tmp);
                    }
                    productsInvolved = getProductListForInvolvedCustomerUpdateLevel(filteredProductUpdates);
                }
            } else {
                stream<customer, persist:Error?> customerResponseStream = sClient->/customers.get(customer, `(product_name = ${productUpdates.productName} AND product_base_version = ${productUpdates.productVersion}) AND customer_key = ${productUpdates.customerKey}`);
                var customerResponse = customerResponseStream.next();
                if customerResponse !is error? {
                    json customerResponseJson = check customerResponse.value.fromJsonWithType();
                    string updateLevel = check customerResponseJson.u2_level;
                    json response = triggerAzureEndpointCiBuild(productUpdates.productName, productUpdates.productVersion, "hotfix update", updateLevel);
                    int ciRunId = check response.id;
                    string ciRunState = check response.state;
                    ciBuildInsertCopy tmp = {
                        ciBuildId: ciRunId,
                        ciStatus: ciRunState,
                        product: productUpdates.productName,
                        version: productUpdates.productVersion,
                        cicdBuildId: UUID,
                        updateLevel: "hotfix_update_level"
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
                ciBuildInsertCopy tmp = {
                    ciBuildId: ciRunId,
                    ciStatus: ciRunState,
                    product: productName,
                    version: productBaseversion,
                    cicdBuildId: UUID,
                    updateLevel: updateLevel
                };
                ciBuildInsertList.push(tmp);
            }
            foreach ciBuildInsertCopy ciBuild in ciBuildInsertList {
                _ = check sClient->executeNativeSQL(`
                INSERT INTO ci_build (ci_build_id, ci_status, product, version, update_level, cicd_buildId)
                VALUES (${ciBuild.ciBuildId}, ${ciBuild.ciStatus}, ${ciBuild.product}, ${ciBuild.version}, ${ciBuild.updateLevel}, ${ciBuild.cicdBuildId});`);
            }
        }
        on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status(@http:Header string? authorization) returns http:Unauthorized|http:Ok {
        string accessToken = regex:split(<string>authorization, " ")[1];
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

    isolated resource function post builds/cd/trigger(@http:Header string? authorization) returns http:Unauthorized|http:Ok {
        string accessToken = regex:split(<string>authorization, " ")[1];
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
                            cdBuildInsertCopy tmp = {
                                cdBuildId: -1,
                                cdStatus: "failed",
                                customer: customer,
                                cicdBuildId: cicdId
                            };
                            _ = check sClient->executeNativeSQL(`
                                    INSERT INTO cd_build (cd_build_id, cd_status, customer, cicd_buildId)
                                    VALUES (${tmp.cdBuildId}, ${tmp.cdStatus}, ${tmp.customer}, ${tmp.cicdBuildId});`);
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
    isolated resource function post builds/cd/status(@http:Header string? authorization) returns http:Unauthorized|http:Ok {
        string accessToken = regex:split(<string>authorization, " ")[1];
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
