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
    resource function post subscriber(http:Caller caller, http:Request request) returns error? {
        xmlns "http://soap.sforce.com/2005/09/outbound" as notification;
        xml response = check request.getXmlPayload();

        json notificationIdObject = check jsonutils:fromXML(response/**/<notification:Id>);
        json sObject = check jsonutils:fromXML(response/**/<notification:sObject>/<*>);

        check addRowToGoogleSheet(notificationIdObject, sObject);
        xml ack = xml `<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                        xmlns:out="http://soap.sforce.com/2005/09/outbound">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <out:notificationsResponse>
                                <out:Ack>true</out:Ack>
                            </out:notificationsResponse>
                        </soapenv:Body>
                        </soapenv:Envelope>`;

        _ = check caller->respond(ack);   
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
