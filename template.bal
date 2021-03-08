import ballerina/http;
import ballerina/jsonutils;
import ballerina/log;
import ballerinax/googleapis_sheets as sheets;

configurable string sheets_refreshToken = ?;
configurable string sheets_clientId = ?;
configurable string sheets_clientSecret = ?;
configurable string sheets_spreadSheetID = ?;
configurable string sheets_workSheetName = ?;

sheets:SpreadsheetConfiguration spreadsheetConfig = {
    oauthClientConfig: {
        clientId: sheets_clientId,
        clientSecret: sheets_clientSecret,
        refreshUrl: sheets:REFRESH_URL,
        refreshToken: sheets_refreshToken
    }
};

sheets:Client spreadsheetClient = checkpanic new (spreadsheetConfig);

service / on new http:Listener(8080) {
    string[] infoArray = [];
    string[] headerArray = [];
    resource function post subscriber(http:Caller caller, http:Request request) {
        xmlns "http://soap.sforce.com/2005/09/outbound" as notification;
        xml response = checkpanic request.getXmlPayload();
        json|error notificationIdObject = jsonutils:fromXML(response/**/<notification:Id>);
        json|error sObject = jsonutils:fromXML(response/**/<notification:sObject>/<*>);

        if (notificationIdObject is json) {
            if (sObject is json) {
                addRowToGoogleSheet(notificationIdObject, sObject);
            } else {
                log:printError("Error in accessing the notification id info");
            }
        } else {
            log:printError("Error in accessing the notification id info");
        }
   
        xml ack = xml `<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                        xmlns:out="http://soap.sforce.com/2005/09/outbound">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <out:notificationsResponse>
                                <out:Ack>true</out:Ack>
                            </out:notificationsResponse>
                        </soapenv:Body>
                      </soapenv:Envelope>`;

        _ = checkpanic caller->respond(ack);
    }
}

function addRowToGoogleSheet(json idObject, json sObject) {
    string[] infoArray = [];
    string[] headerArray = [];   

    headerArray.push(NOTIFICATION_ID);
    string idString = let var id = idObject.Id.Id in id is json ? id.toString() : "";
    infoArray.push(idString);
    json[] contactInfoJson = <json[]>sObject;

    foreach var item in contactInfoJson {
        map<json> sObjectMap = <map<json>>item;
        _ = sObjectMap.removeIfHasKey(NAMESPACE_KEY);
        foreach var ['key, value] in sObjectMap.entries() {
            headerArray.push('key.toString());
            infoArray.push(value.toString());
        }
    }

    var headers = spreadsheetClient->getRow(sheets_spreadSheetID, sheets_workSheetName, 1);
    if(headers == []){
        error? appendResult = checkpanic spreadsheetClient->appendRowToSheet(sheets_spreadSheetID, sheets_workSheetName, 
            headerArray);
        if (appendResult is error) {
            log:printError(appendResult.message());
        }
    }
    error? appendResult = checkpanic spreadsheetClient->appendRowToSheet(sheets_spreadSheetID, 
                sheets_workSheetName, infoArray);
}
