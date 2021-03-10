import ballerina/http;
import ballerina/jsonutils;
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
        xml payload = check request.getXmlPayload();

        xmlns "http://soap.sforce.com/2005/09/outbound" as notification;
        json notificationIdObject = check jsonutils:fromXML(payload/**/<notification:Id>);
        json contactInfoObject = check jsonutils:fromXML(payload/**/<notification:sObject>/<*>);

        check addRowToGoogleSheet(notificationIdObject, contactInfoObject);
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

function addRowToGoogleSheet(json idObject, json contactInfoObject) returns error? {
    string[] infoArray = [];
    string[] headerArray = [];

    string idString = let var id = idObject.Id.Id in id is json ? id.toString() : EMPTY_STRING;
    infoArray.push(idString);
    headerArray.push(NOTIFICATION_ID);

    json[] contactInfoArray = <json[]>contactInfoObject;
    foreach var item in contactInfoArray {
        map<json> itemMap = <map<json>>item;
        _ = itemMap.removeIfHasKey(NAMESPACE_KEY);
        foreach var ['key, value] in itemMap.entries() {
            infoArray.push(value.toString());
            string replacedString = regex:replaceFirst('key.toString(), SF_NAMESPACE_REGEX, EMPTY_STRING);
            headerArray.push(replacedString);
        }
    }
    var headers = spreadsheetClient->getRow(sheets_spreadsheet_id, sheets_worksheet_name, HEADER_ROW);
    if(headers == []){
        _ = check spreadsheetClient->appendRowToSheet(sheets_spreadsheet_id, sheets_worksheet_name, headerArray);
    }
    _ = check spreadsheetClient->appendRowToSheet(sheets_spreadsheet_id, sheets_worksheet_name, infoArray);
}
