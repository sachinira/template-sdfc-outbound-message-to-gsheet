import ballerina/http;
import ballerina/jsonutils;
import ballerina/log;
import ballerina/regex;
import ballerinax/googleapis_sheets as sheets;

configurable string sheets_refresh_token = ?;
configurable string sheets_client_id = ?;
configurable string sheets_client_secret = ?;
configurable string sheets_spreadsheet_id = ?;
configurable string sheets_worksheet_name = ?;

sheets:SpreadsheetConfiguration spreadsheetConfig = {
    oauthClientConfig: {
        clientId: sheets_client_id,
        clientSecret: sheets_client_secret,
        refreshUrl: sheets:REFRESH_URL,
        refreshToken: sheets_refresh_token
    }
};

sheets:Client spreadsheetClient = checkpanic new (spreadsheetConfig);

service / on new http:Listener(8080) {
    resource function post subscriber(http:Caller caller, http:Request request) {
        xmlns "http://soap.sforce.com/2005/09/outbound" as notification;
        xml|error response = request.getXmlPayload();

        if (response is xml) {
            json|error notificationIdObject = jsonutils:fromXML(response/**/<notification:Id>);
            json|error sObject = jsonutils:fromXML(response/**/<notification:sObject>/<*>);

            if (notificationIdObject is json) {
                if (sObject is json) {
                    checkpanic addRowToGoogleSheet(notificationIdObject, sObject);
                } else {
                    log:printError("Error in accessing the sobject");
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
        } else {
            log:printError("Error in accessing XML payload");
        }
        
    }
}

function addRowToGoogleSheet(json idObject, json sObject) returns error? {
    string[] infoArray = [];
    string[] headerArray = [];

    headerArray.push(NOTIFICATION_ID);
    string idString = let var id = idObject.Id.Id in id is json ? id.toString() : EMPTY_STRING;
    infoArray.push(idString);
    json[] contactInfoJson = <json[]>sObject;

    foreach var item in contactInfoJson {
        map<json> sObjectMap = <map<json>>item;
        _ = sObjectMap.removeIfHasKey(NAMESPACE_KEY);
        foreach var ['key, value] in sObjectMap.entries() {
            string replacedString = regex:replaceFirst('key.toString(), SF_NAMESPACE_REGEX, EMPTY_STRING);
            headerArray.push(replacedString);
            infoArray.push(value.toString());
        }
    }
    var headers = spreadsheetClient->getRow(sheets_spreadsheet_id, sheets_worksheet_name, 1);
    if(headers == []){
        error? appendResult = check spreadsheetClient->appendRowToSheet(sheets_spreadsheet_id, sheets_worksheet_name, 
            headerArray);
        if (appendResult is error) {
            log:printError(appendResult.message());
        }
    }
    error? appendResult = check spreadsheetClient->appendRowToSheet(sheets_spreadsheet_id, sheets_worksheet_name, 
        infoArray);
}
