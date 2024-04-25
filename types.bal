type CustomerInsertCopy record {|
    string customerKey;
    string environment;
    string productName;
    string productBaseversion;
    string u2Level;
|};

type CiBuildInfo record {|
    string product;
    string version;
    string status;
    string consoleErrorUrl;
|};

type CdBuildInfo record {|
    string customer;
    string status;
    string consoleErrorUrl;
|};

type Chunkinfo record {|
    string id;
    CiBuildInfo[] ciBuild;
    CdBuildInfo[] cdBuild;
|};

type ProductRegularUpdate record {|
    string productName;
    string productBaseversion;
|};

type ProductHotfixUpdate record {|
    string productName;
    string productVersion;
    string customerKey;
    string hotfixFilePath;
|};

type AcrImageList record {|
    string[]|() repositories;
|};

type DeletedImage record {|
    string[] manifestsDeleted;
    string[] tagsDeleted;
|};

type TimelineRecord record {
    string result;
};

type TimelineTask record {
    TimelineRecord[] records;
};

type users record {|
    string username;
    string password;
|};

type auth record {|
    users users;
|};

type bal record {|
    auth auth;
|};
