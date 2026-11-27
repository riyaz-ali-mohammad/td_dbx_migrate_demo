-- Converted the Teradata SET table to Delta, removed the unmapped source database qualifier, and stripped Teradata storage and distribution options.
-- Converted INTEGER to INT, removed CHARACTER SET LATIN, and preserved NOT CASESPECIFIC behavior with UTF8_LCASE collation.
-- TODO: manual review required — Teradata SET and UNIQUE PRIMARY INDEX uniqueness is not enforced by Delta; enforce uniqueness in the write path.
CREATE TABLE SANC_TOKEN_STG (
    GROUP_ID INT NOT NULL,
    NAME_SEQ_NR SMALLINT NOT NULL,
    TOKEN_SEQ_NR SMALLINT NOT NULL,
    TOKEN_TXT VARCHAR(60) COLLATE UTF8_LCASE
);

-- Converted the UNIQUE PRIMARY INDEX to an informational Delta primary key.
ALTER TABLE SANC_TOKEN_STG
ADD CONSTRAINT XPKSANC_TOKEN_STG PRIMARY KEY (GROUP_ID, NAME_SEQ_NR, TOKEN_SEQ_NR);
