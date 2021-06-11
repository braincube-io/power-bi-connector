section Braincube;

/********************** APIKEY AUTH CONSTANTS *************************/
me_uri = "https://mybraincube.com/sso-server/ws/user/me";

//Function executed as a main, called after the authentification
//Call the GetBraincube after displaying the date picker to choose parameters
[DataSource.Kind="Braincube", Publish="Braincube.Publish"]
shared Braincube.Contents = () => GetBraincubes();

/**********************************************************************************************************
                                            DATA SELECTION
***********************************************************************************************************/
//Return a Navigation Table with all the braincubes availablesfor this client, without the MX
GetBraincubes = () as table =>
    let
        //retrieve a session with the API Key
        apiKey = Extension.CurrentCredential()[Key],
        ssosession = Braincube.authenticatedGet(me_uri, apiKey),
        sso = Json.Document(ssosession),
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
                () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
                each [i] <= List.Count(sso[accessList]),
                each [
                    tab = if(Text.Contains(sso[accessList]{[i]}[product][type], "braincube") <> false) then
                    Table.InsertRows([tab], Table.RowCount([tab]), {[
                        Name=sso[accessList]{[i]}[product][name],
                        Key=sso[accessList]{[i]}[product][productId],
                        Data=GetMemoryBases(sso[accessList]{[i]}[product][name], sso, apiKey),
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
GetMemoryBases = (braincubeName as text, sso as record, apiKey as text) as table =>
    let
        //Call the REST API to retrieve MB infos for the selected braincube
        mb = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/all/selector", apiKey),
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
                        Data= GetPeriod(memoryBases{[i]}[bcId],braincubeName, sso, apiKey),
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

// Manage period selector
GetPeriod = (mbId as number,braincubeName as text, sso as record, apiKey as text) as table =>
    let
       periodValue = {2,7,14,30,60,90,120,180,360},
       DataTable = List.Generate(
               () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
               each [i] <= List.Count(periodValue),
               each [                   
                   tab = Table.InsertRows([tab], Table.RowCount([tab]), {[
                       Name=Number.ToText([i]) & " - Last " & Number.ToText(periodValue{[i]}) & " days",
                       Key= periodValue{[i]},
                       Data= GetVariables(mbId, braincubeName, sso, apiKey, periodValue{[i]}),
                       ItemKind= "CubeView",
                       ItemName= "CubeView",
                       IsLeaf= false]}
                   ),
                   i=[i]+1
               ]
           ),
            NavTable = Table.ToNavigationTable(DataTable{List.Count(DataTable)-1}[tab], {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
         in
            NavTable;

//Return the variables availables for the selected memorybase
GetVariables = (mbId as number, braincubeName as text, sso as record, apiKey as text, periodValue as number) as table =>
    let
        //Call the REST API to retrieve usefull infos about the MB
        ref = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) & "/simple", apiKey),
        reference = Json.Document(ref),
        //Call the REST API to retrieve name of the variables for the selected MB
        var = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/" & Text.From(mbId) &"/variables/selector", apiKey),
        variables = Json.Document(var)[items],
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
            () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
            each [i] < List.Count(variables),
            each [
                tab = Table.InsertRows([tab], Table.RowCount([tab]), {[
                    Name=variables{[i]}[local],
                    Key=variables{[i]}[id],
                    Data= GetVariableContent(variables{[i]}[local], braincubeName, mbId, variables{[i]}[id], reference, sso, apiKey, periodValue),
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
    varName as text, braincubeName as text, mbId as number, varId as number, ref, sso as record, apiKey as text, periodValue as number
) as table =>
    let
        endDate = DateTime.Date(DateTime.LocalNow()),
        beginDate = Date.AddDays(endDate,-(periodValue)),
        //Formats the data requested by the API to provide the response
        content= Json.FromValue(
            [order= ref[referenceDate],
                definitions= {ref[referenceDate], "mb" & Text.From(mbId) & "/d" & Text.From(varId)} ,
                context=[
                    dataSource = "mb" & Text.From(mbId),
                    filter=[BETWEEN={ref[order], Date.ToText(beginDate, "yyyyMMdd") & "_000000", Date.ToText(endDate, "yyyyMMdd") & "_235959"}]]
            ]
        ),
        //Call the REST API to get the values needed
        var=Web.Contents("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) & "/LF", [
            Headers = [
                #"Accept" = "application/json",
                #"X-Api-Key" = apiKey,
                #"Content-Type" = "application/json"
            ],
            Content = content,
            ManualCredentials = true]
        ),
        variables = Json.Document(var),
        //Formats the values to return a table usable by PowerBI
        tab = Table.FromList(variables[datadefs]{0}[data], null, {"_Order"}),
        values = Table.AddColumn(tab, varName, each variables[datadefs]{1}[data]{List.PositionOf(variables[datadefs]{0}[data], [_Order])}),
        formatTab = Table.ReplaceValue(values, "?", "No value", Text.Replace, {"_Order", varName}),
        // On convertir la colonne _Order en datetime si le `type` est DATETIME
        transformOrderValue = Table.TransformColumns(formatTab, {{"_Order", each convertData(_,variables[datadefs]{0}[type])}}),
        // On convertir la colonne varname en datetime si le `type` est DATETIME
        transformValues = Table.TransformColumns(transformOrderValue, {{varName, each convertData(_,variables[datadefs]{1}[type])}}),
        result = Table.AddIndexColumn(transformValues, "_Index", 0,1)
    in
        result;

/***************************************************************************************************************
                                               UTILS POUR CONVERTION FORMAT
****************************************************************************************************************/
// Convertir un TD date braincube en datetime YYYYMMDDTHHMMSS
convertTDToDate = (toConvert as text) as datetime =>
    let
        result = DateTime.FromText(Text.Replace(toConvert,"_","T"))
    in
        result;

// Convertit le texte en datetime si le tye est DATETIME, sinon le retourne tel qu'elle
convertData = (toConvert as text, dataType as text) as any =>
    let
        result = if dataType = "DATETIME" then convertTDToDate(toConvert) else toConvert
    in
        result;
/**********************************************************************************************************************
                                                BRAINCUBE AUTHENTIFICATION
***********************************************************************************************************************/
// Also allow Api Key access
Braincube = [
    Authentication = [
          Key = [KeyLabel = Extension.LoadString("ApiKeyLabel")]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];


Braincube.authenticatedGet = (_uri as text, apiKey as text) as binary =>
    let
        req = Web.Contents(_uri, [
            Headers = [
                #"Accept" = "application/json",
                #"X-Api-Key" = apiKey,
                #"Content-Type" = "application/json"
            ],
            ManualCredentials = true
        ])
    in
        req;
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
    Category = "online services",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/braincube-io/power-bi-connector",
    SourceImage = Braincube.Icons,
    SourceTypeImage = Braincube.Icons
];

Braincube.Icons = [
    Icon16 = { Extension.Contents("Braincube16.png"), Extension.Contents("Braincube20.png"), Extension.Contents("Braincube24.png"), Extension.Contents("Braincube32.png")},
    Icon32 = { Extension.Contents("Braincube32.png"), Extension.Contents("Braincube40.png"), Extension.Contents("Braincube48.png"), Extension.Contents("Braincube64.png")}
];
