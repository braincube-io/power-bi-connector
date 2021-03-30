section Braincube;

/********************** APIKEY AUTH CONSTANTS *************************/
me_uri = "https://mybraincube.com/sso-server/ws/user/me";

//Function executed as a main, called after the authentification
//Call the GetBraincube after displaying the date picker to choose parameters
[DataSource.Kind="Braincube", Publish="Braincube.Publish"]
shared Braincube.Contents = Value.ReplaceType(GetBraincubes, BraincubeSelector);
//shared Braincube.Contents = () => GetBraincubes(#date(2015, 2, 12), #date(2018, 2, 10));

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
        //retrieve a session with the API Key
        ssosession = Braincube.authenticatedGet(me_uri),
        sso = Json.Document(ssosession),
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
                () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
                each [i] <= List.Count(sso[accessList]),
                each [
                    tab = if(Text.Contains(sso[accessList]{[i]}[product][type], "braincube") <> false) then
                    Table.InsertRows([tab], Table.RowCount([tab]), {[
                        Name=sso[accessList]{[i]}[product][name],
                        Key= sso[accessList]{[i]}[product][productId],
                        Data= GetMemoryBases(sso[accessList]{[i]}[product][name], begin, end, sso),
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
GetMemoryBases = (braincubeName as text, begin as date, end as date, sso as record) as table =>
    let
        //Call the REST API to retrieve MB infos for the selected braincube
        mb = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/all/selector"),
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
        ref = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braindata/mb" & Text.From(mbId) & "/simple"),
        reference = Json.Document(ref),
        //Call the REST API to retrieve name of the variables for the selected MB
        var = Braincube.authenticatedGet("https://api.mybraincube.com/braincube/" &  braincubeName & "/braincube/mb/" & Text.From(mbId) &"/variables/selector"),
        variables = Json.Document(var)[items],
        //Generate the Navigation Table with the values
        DataTable = List.Generate(
            () => [i=0, tab=#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, {})],
            each [i] < List.Count(variables),
            each [
                tab = Table.InsertRows([tab], Table.RowCount([tab]), {[
                    Name=variables{[i]}[local],
                    Key=variables{[i]}[id],
                    Data= GetVariableContent(variables{[i]}[local], braincubeName, mbId, variables{[i]}[id], reference, begin, end, sso),
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
                #"X-Api-Key" = Extension.CurrentCredential()[Key],
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
        result = Table.AddIndexColumn(formatTab, "_Index", 0,1)
    in
        result;


/**********************************************************************************************************************
                                                BRAINCUBE AUTHENTIFICATION
***********************************************************************************************************************/
// Also allow Api Key access
Braincube = [
    Authentication = [
          Key = [KeyLabel = Extension.LoadString("ApiKeyLabel")]
          //Anonymous = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];


Braincube.authenticatedGet = (_uri as text) as binary =>
    let
        req = Web.Contents(_uri, [
            Headers = [
                #"Accept" = "application/json",
                #"X-Api-Key" = Extension.CurrentCredential()[Key],
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
