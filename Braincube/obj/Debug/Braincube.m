section Braincube;

client_id = "83f2c2f0-319f-381f-b7e3-8e74e8469e22"; 
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
info_uri = "https://mybraincube.com/sso-server/ws/oauth2/me";
token_uri="https://mybraincube.com/sso-server/rest/session/openWithToken";
authorize_uri="https://mybraincube.com/sso-server/vendors/braincube/authorize.jsp";
scope ="BASE API";

[DataSource.Kind="Braincube", Publish="Braincube.Publish"]
//Function executed as a main, called after the authentification
//Call the GetBraincube after displaying the date picker to choose parameters
shared Braincube.Contents = Value.ReplaceType(GetBraincubes, BraincubeSelector);

/*********************************************************************************************************
                                               DATE PICKER
*********************************************************************************************************/
//Allow the user to select two dates (begin and end) which are passed as parameters to GetBraincubes
BraincubeSelector = type function (
    begin as (type date meta [
        Documentation.FieldCaption = "The starting date",
        Documentation.FieldDescription = "The starting date"
    ]),
    end as (type date meta [
        Documentation.FieldCaption = "The end date",
        Documentation.FieldDescription = "The end date"
    ]))
    as table meta [
        Documentation.Name = "Select the time interval in which you want to retrieve your data"
    ];

/**********************************************************************************************************
                                            DATA SELECTION
***********************************************************************************************************/
//Return a Navigation Table with all the braincubes availablesfor this client, without the MX
GetBraincubes = (begin as date, end as date) as table => 
    let
        //Call the REST API to retrieve the braincubes
        source = Web.Contents(info_uri, [
            Headers = [
                #"Authorization" = "Bearer" & Extension.CurrentCredential()[access_token]
            ]]
        ),
        data = Json.Document(source)[allowedProducts],
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
                () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
                each [i] <= List.Count(data),
                each [
                    tab = if(Text.Contains(data{[i]}[name], "MX_") <> true) then
                    Table.InsertRows([tab], Table.RowCount([tab]), {[
                        Name=data{[i]}[name],
                        Key= data{[i]}[id],
                        Data= GetMemoryBases(data{[i]}[name], begin, end),
                        ItemKind= "Cube",
                        ItemName= "Cube",
                        IsLeaf= false]}
                    )
                    else
                    Table.InsertRows([tab], Table.RowCount([tab]), {}),
                    i=[i]+1
                ]
            ),
            NavTable = Table.ToNavigationTable(DataTable{List.Count(DataTable)-1}[tab], {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
         in
            NavTable;

//Return a Navigation Table with all the memoryBases available for the selected braincube
GetMemoryBases = (braincubeName as text, begin as date, end as date) as table => 
    let 
        //retrieve a SSO token to access REST API
        ssosession = Web.Contents(token_uri, [
            Headers = [
                #"Authorization" = "Bearer " & Extension.CurrentCredential()[access_token]
            ]]
        ),
        sso = Json.Document(ssosession),
        //Call the REST API to retrieve MB infos for the selected braincube
        mb = Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/all/selector", [
            Headers = [
                #"IPLSSOTOKEN" = sso[token]
            ]]
        ), 
        memoryBases = Json.Document(mb)[items],
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
            () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
            each [i] < List.Count(memoryBases),
            each [
                tab = if(memoryBases{[i]}[quickStudy] <> true) then 
                    Table.InsertRows([tab], Table.RowCount([tab]), {[
                        Name=memoryBases{[i]}[name] & " - " & Text.From(memoryBases{[i]}[numberOfVariables]) & " variables",
                        Key=  memoryBases{[i]}[bcId],
                        Data= GetVariables(memoryBases{[i]}[bcId], braincubeName, begin, end, sso),
                        ItemKind= "Database",
                        ItemName= "Database",
                        IsLeaf= false]}
                    )
                    else
                    Table.InsertRows([tab], Table.RowCount([tab]), {}),
                i=[i]+1 
            ]
        ),
        NavTable = Table.ToNavigationTable(DataTable{List.Count(DataTable)-1}[tab], {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
     in
       NavTable;

//Return the variables availables for the selected memorybase
GetVariables = (mbId as number, braincubeName as text, begin as date, end as date, sso as record) as table =>
    let 
        //Call the REST API to retrieve usefull infos about the MB
        ref = Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) & "/simple", [
            Headers = [
                #"IPLSSOTOKEN" = sso[token]
            ]]
        ), 
        reference = Json.Document(ref),
        //Formats the data requested by the API to provide the response
        content= Json.FromValue(
            [order= reference[referenceDate], 
                definitions= {reference[referenceDate]} , 
                context=[
                    dataSource = "mb" & Text.From(mbId), 
                    filter=[BETWEEN={reference[order], Date.ToText(begin, "yyyyMMdd_hhmmss"), Date.ToText(end, "yyyyMMdd_hhmmss")}]]
            ] 
        ),
        //Call the REST API to get the order variable of the MB
        order=Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) &"/LF", [ 
            Headers = [
                #"Accept" = "application/json",
                #"IPLSSOTOKEN" = sso[token],
                #"Content-Type" = "application/json"
            ],
            Content = content]
        ), 
        orderTab=Table.FromList(Json.Document(order)[datadefs]{0}[data], null, {"_Order"}),
        //Call the REST API to retrieve name of the variables for the selected MB
        var=Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/" & Text.From(mbId) &"/variables/selector", [
            Headers = [
                #"IPLSSOTOKEN" = sso[token]
            ]]
        ), 
        variables = Json.Document(var)[items],
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
            () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
            each [i] < List.Count(variables),
            each [
                tab = Table.InsertRows([tab], Table.RowCount([tab]), {[
                    Name=variables{[i]}[local],
                    Key=variables{[i]}[id],
                    Data= GetVariableContent(variables{[i]}[local], braincubeName, mbId, variables{[i]}[id], reference, begin, end, orderTab, sso),
                    ItemKind= "Record",
                    ItemName= "Record",
                    IsLeaf= true]}
                ),
                i=[i]+1
            ]
        ),
        NavTable = Table.ToNavigationTable(DataTable{List.Count(DataTable)-1}[tab], {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;
        
/***************************************************************************************************************
                                                DATA RETRIEVE
****************************************************************************************************************/
//Return all the values of the selected variable between te interval of time specified
//Return a table with three columns : the values, the order (a variable, same for the variables in the same MB), and the 
//index because PowerBI does not recognize order values as a link between variables
shared GetVariableContent = (
    varName as text, 
    braincubeName as text,
    mbId as number,
    varId as number, 
    ref, 
    begin as date, 
    end as date,
    orderTab as table,
    sso as record
) as table =>
    let
        //Formats the data requested by the API to provide the response
        content= Json.FromValue(
            [order= ref[referenceDate], 
                definitions= {ref[referenceDate], "mb" & Text.From(mbId) & "/d" & Text.From(varId)} , 
                context=[
                    dataSource = "mb" & Text.From(mbId), 
                    filter=[BETWEEN={ref[order], Date.ToText(begin, "yyyyMMdd_hhmmss"), Date.ToText(end, "yyyyMMdd_hhmmss")}]]
            ] 
        ),
        //Call the REST API to get the values needed
        var=Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) &"/LF", [ 
            Headers = [
                #"Accept" = "application/json",
                #"IPLSSOTOKEN" = sso[token],
                #"Content-Type" = "application/json"
            ],
            Content = content]
        ), 
        variables = Json.Document(var),
        //Formats the values to return a table usable by PowerBI
        values = Table.AddColumn(orderTab, varName, each variables[datadefs]{1}[data]{List.PositionOf(variables[datadefs]{0}[data], [_Order])}),
        formatTab = Table.ReplaceValue(values, "?", "No value", Text.Replace, {"_Order", varName}),
        result = Table.AddIndexColumn(formatTab, "_Index", 0,1)
    in
        result;

/**********************************************************************************************************************
                                                BRAINCUBE AUTHENTIFICATION
***********************************************************************************************************************/
//Implement an OAuth2 authentification, by calling the athorization page of braincube, and retrieving the token from the URL
Braincube = [
    Authentication = [
        OAuth = [StartLogin = StartLogin, FinishLogin = FinishLogin]
    ], Label = "Braincube Connector"
];

//Call and display the autorization page of Braincube with all the stuff needed to get the token
StartLogin = (resourceUrl, state, display) =>
  let
      authorizeUrl = authorize_uri & "?" & Uri.BuildQueryString([
            client_id = client_id,  
            redirect_uri = redirect_uri,
            state = state,
            scope =scope,
            response_type = "token"
      ])
  in
    [
      LoginUri = authorizeUrl,
      CallbackUri = redirect_uri,
      WindowHeight = 600,
      WindowWidth = 800,
      Context = null
    ];

//Retrieves the part of the URL returned by the authentication that contains the token
//Token store in the Credential logic of PowerBI, accessible everywhere after
FinishLogin = (context, callbackUri, state) =>
    let
        fragments=Uri.Parts(callbackUri)[Fragment],
        frag=Text.AfterDelimiter(fragments, "access_token="),
        token=Text.BeforeDelimiter(frag, "&"),
        result = [access_token  = token]
    in
        result;

/**********************************************************************************************************************
                                                    UTILS
**********************************************************************************************************************/
//Function to display the Navigation Tables graphically
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

Braincube.Publish = [
    Beta = true,
    Category = "online services",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Braincube.Icons,
    SourceTypeImage = Braincube.Icons
];

Braincube.Icons = [
    Icon16 = { Extension.Contents("Braincube16.png"), Extension.Contents("Braincube20.png"), Extension.Contents("Braincube24.png"), Extension.Contents("Braincube32.png")},
    Icon32 = { Extension.Contents("Braincube32.png"), Extension.Contents("Braincube40.png"), Extension.Contents("Braincube48.png"), Extension.Contents("Braincube64.png")}
];
