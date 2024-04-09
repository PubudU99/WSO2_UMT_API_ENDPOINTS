import ballerina/http;
import ballerina/io;
import ballerina/persist;
import ballerina/regex;
import ballerina/sql;
import ballerina/uuid;

listener http:Listener endpoint = new (5000);

final Client sClient = check initializeClient();

service /cst on endpoint {

    isolated resource function post .(CustomerInsertCopy[] list) returns string[]|persist:Error {
        customerInsert[] cstInfoList = getCustomersToInsert(list);
        return sClient->/customers.post(cstInfoList);
    }

    isolated resource function get customer() returns customer[]|persist:Error {
        stream<customer, persist:Error?> response = sClient->/customers;
        return check from customer customer in response
            select customer;
    }

    isolated resource function post builds(http:Caller caller, ProductRegularUpdate[]|ProductHotfixUpdate product_updates) {
        do {
            string UUID = uuid:createType4AsString();
            check caller->respond(UUID);
            cicd_build insertCicdbuild = check insertCicdBuild(UUID);
            ci_buildInsert[] ciBuildInsertList = [];

            if product_updates is ProductRegularUpdate[] {
                foreach ProductRegularUpdate product in product_updates {
                    json response = triggerAzureEndpointCiBuild(product.productName, product.productBaseversion);
                    io:println(response);
                    int ciRunId = check response.id;
                    string ciRunState = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        ci_build_id: ciRunId,
                        ci_status: ciRunState,
                        product: product.productName,
                        version: product.productBaseversion,
                        cicd_buildId: insertCicdbuild.id
                    };
                    ciBuildInsertList.push(tmp);
                }

                string[] productsInvolved = getProductListForInvolvedCustomerUpdateLevel(product_updates);
                string[] imagesNotInAcr = getImageNotInACR(productsInvolved);

                foreach string product in imagesNotInAcr {
                    string productName = regex:split(product, "-")[0];
                    string productBaseversion = regex:split(product, "-")[1];
                    string updateLevel = regex:split(product, "-")[2];
                    json response = triggerAzureEndpointCiBuild(productName, productBaseversion, updateLevel);
                    io:println(response);
                    int ciRunId = check response.id;
                    string ciRunState = check response.state;
                    ci_buildInsert tmp = {
                        id: uuid:createType4AsString(),
                        ci_build_id: ciRunId,
                        ci_status: ciRunState,
                        product: productName,
                        version: productBaseversion,
                        cicd_buildId: insertCicdbuild.id
                    };
                    ciBuildInsertList.push(tmp);
                }

                // io:println(ciBuildInsertList);

                // Trigger the pipeline for the other products which used by the customers

                string[] _ = check sClient->/ci_builds.post(ciBuildInsertList);

            }
        } on fail var e {
            io:println("Error in resource function trigger CI builds.");
            io:println(e);
        }
    }

    isolated resource function post builds/ci/status() returns error? {
        sql:ParameterizedQuery whereClause = `ci_result = "inProgress"`;
        string[] CiPendingCicdIdList = getCiPendingCicdIdList(whereClause);
        updateCiStatus(CiPendingCicdIdList);
        updateCiStatusCicdTable(CiPendingCicdIdList);
    }

    isolated resource function post builds/cd/trigger() returns error? {
        sql:ParameterizedQuery whereClause = `ci_result = "inProgress" OR ci_result = "succeeded"`;
        string[] CiPendingCicdIdList = getCiPendingCicdIdList(whereClause);
        foreach string cicdId in CiPendingCicdIdList {
            map<int> mapProductCiId = getMapProductCiId(cicdId);
            string[] productList = mapProductCiId.keys();
            map<string[]> mapCustomerCiList = createMapCustomerCiList(productList, mapProductCiId);
            map<string> mapCiIdState = getMapCiIdState(mapProductCiId);
            foreach string customer in mapCustomerCiList.keys() {
                boolean flag = true;
                string[] buildIdList = <string[]>mapCustomerCiList[customer];
                foreach string buildId in buildIdList {
                    if "failed".equalsIgnoreCaseAscii(mapCiIdState.get(buildId)) {
                        flag = false;
                        io:println(customer + " customer's CD pipline cancelled");
                        cicd_build _ = check sClient->/cicd_builds/[cicdId].put({
                            cd_result: "failed due to ci build fail"
                        });
                        break;
                    } else if "inProgress".equalsIgnoreCaseAscii(mapCiIdState.get(buildId)) {
                        flag = false;
                        io:println("Still building the image of customer " + customer);
                        break;
                    }
                }
                if flag {
                    updateCdResultCicdTable(cicdId);
                    insertNewCdBuilds(cicdId, customer);
                }
            }
        }
    }
    isolated resource function post builds/cd/status() returns error? {
        updateInProgressCdBuilds();
    }

    isolated resource function get builds/[string cicdId]() returns Chunkinfo {
        CiBuildInfo[] ciBuild = getCiBuildinfo(cicdId);
        CdBuildInfo[] cdBuild = getCdBuildinfo(cicdId);
        Chunkinfo chunkInfo = {
            id: cicdId,
            ciBuild: ciBuild,
            cdBuild: cdBuild
        };
        return chunkInfo;
    }

    isolated resource function post builds/[string cicdId]/re\-trigger() {
        retriggerFailedCiBuilds(cicdId);
        updateCiCdStatusOnRetriggerCiBuilds(cicdId);
        deleteFailedCdBuilds(cicdId);
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

        // Mark the last 5 images created as true
        int imageLength = acrImageList.length();
        if imageLength > 5 {
            acrImageListMap[acrImageList[imageLength - 1]] = true;
            acrImageListMap[acrImageList[imageLength - 2]] = true;
            acrImageListMap[acrImageList[imageLength - 3]] = true;
            acrImageListMap[acrImageList[imageLength - 4]] = true;
            acrImageListMap[acrImageList[imageLength - 5]] = true;
        }

        // Filter the images which are in value false that need to be deleted
        map<boolean> cleanupAcrImagelistMap = acrImageListMap.filter(image => image == false);

        // Delete the images
        foreach string image in cleanupAcrImagelistMap.keys() {
            http:Client acrEndpoint = check getAcrEndpoint();
            DeletedImage _ = check acrEndpoint->/[image].delete();
        }
    }

    // isolated resource function get hai() returns AcrImageList|http:ClientError{
    //     return check getAcrImageList();
    // }
}
