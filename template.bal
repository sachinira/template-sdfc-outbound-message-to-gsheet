import ballerina/io;
import ballerina/http;
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
    resource function post subscriber(http:Caller caller, http:Request request) {

        xmlns "http://soap.sforce.com/2005/09/outbound" as notification;
        xml response = checkpanic request.getXmlPayload();

        io:println(response/**/<notification:Notification>);
        xml value = response/**/<notification:Notification>;

        error? appendResult = checkpanic spreadsheetClient->appendRowToSheet(sheets_spreadSheetID, 
                    sheets_workSheetName, [value.toString()]);

        xml ack = xml `<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:out="http://soap.sforce.com/2005/09/outbound">
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
