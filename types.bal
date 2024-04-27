type CustomerInsertCopy record {|
    string customerKey;
    string environment;
    string productName;
    string productBaseversion;
    string u2Level;
|};

type ciBuildInsertCopy record {|
    int ciBuildId;
    string ciStatus;
    string product;
    string version;
    string cicdBuildId;
    string updateLevel;
|};

type cdBuildInsertCopy record {
    int cdBuildId;
    string cdStatus;
    string customer;
    string cicdBuildId;
};

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
    int id;
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
