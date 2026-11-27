-- TODO: manual review required — Teradata SET table full-row uniqueness is not enforced by Delta; enforce de-duplication against existing and incoming rows in the write path
-- TODO: manual review required — confirm fixed-width CHAR padding and trailing-space behavior for PARTY_ID and ALIAS_TYP_CD consumers
-- TODO: manual review required — confirm the preserved VARCHAR bounds match the source write-path overflow contract
-- Converted the two-part source name to unqualified PARTY_ALIAS because no target Unity Catalog mapping was supplied.
-- Removed Teradata FALLBACK, journals, CHECKSUM, MERGEBLOCKRATIO, and MAP physical-storage clauses; Delta manages durability and layout.
-- Removed LATIN character-set clauses, translated NOT CASESPECIFIC to UTF8_LCASE collation, and removed display-only TIMESTAMP FORMAT.
-- Replaced the Teradata unique primary index distribution with liquid clustering; its uniqueness contract is added separately as an informational primary key.
CREATE TABLE PARTY_ALIAS (
    PARTY_ID CHAR(12) COLLATE UTF8_LCASE NOT NULL,
    ALIAS_SEQ_NR SMALLINT NOT NULL,
    ALIAS_NM VARCHAR(100) COLLATE UTF8_LCASE,
    ALIAS_NORM_NM VARCHAR(100) COLLATE UTF8_LCASE,
    ALIAS_TYP_CD CHAR(2) COLLATE UTF8_LCASE,
    CO_UPD_TMS TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (PARTY_ID, ALIAS_SEQ_NR);

-- TODO: manual review required — Delta primary keys are informational; enforce uniqueness of (PARTY_ID, ALIAS_SEQ_NR) in the write path
-- Preserved the UNIQUE PRIMARY INDEX key contract as an informational primary key constraint.
ALTER TABLE PARTY_ALIAS
ADD CONSTRAINT XPKPARTY_ALIAS PRIMARY KEY (PARTY_ID, ALIAS_SEQ_NR);
