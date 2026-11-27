-- TODO: manual review required — Teradata SET table row-uniqueness is lost (Delta is multiset); de-dup at load with a controlled SELECT DISTINCT / MERGE write path
-- Converted the Teradata table to an unqualified Delta table because no target catalog mapping was supplied; stripped Teradata storage, journaling, map, and display-format clauses
CREATE TABLE XBORDER_FLOW_MTH (
    YR_MON INT NOT NULL,
    CTRY_2_CD CHAR(2) COLLATE UTF8_LCASE NOT NULL,
    DR_CR_IND CHAR(1) COLLATE UTF8_LCASE NOT NULL,
    FATF_STATUS_CD CHAR(2) COLLATE UTF8_LCASE,
    CTRY_RISK_CD CHAR(1) COLLATE UTF8_LCASE,
    TXN_CNT INT,
    GBP_AMT DECIMAL(18,2),
    PARTY_CNT INT,
    CO_UPD_TMS TIMESTAMP_NTZ
);

-- TODO: manual review required — the informational Delta primary key does not enforce the source UNIQUE PRIMARY INDEX; enforce key uniqueness in the write path
-- Converted the Teradata UNIQUE PRIMARY INDEX to an informational Delta primary key
ALTER TABLE XBORDER_FLOW_MTH
ADD CONSTRAINT XPKXBORDER_FLOW_MTH PRIMARY KEY (YR_MON, CTRY_2_CD, DR_CR_IND);
