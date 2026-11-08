-- =====================================================================
-- 07: Data discovery
-- Checks the raw data before writing any cleanup logic.
-- Each check notes WHY it matters and the DECISION it led to.
-- Read-only: runs as DEVELOPER against the real source data in PROD_RAW.
-- =====================================================================

USE ROLE DEVELOPER;
USE WAREHOUSE RLI_DEV_WH;
USE SCHEMA PROD_RAW.INSURANCE;


-- ---------------------------------------------------------------------
-- 0. Did every row load?  Expect 352 / 1004 / 425 / 3554 / 50
-- ---------------------------------------------------------------------
SELECT 'CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM CUSTOMERS
UNION ALL SELECT 'POLICIES',     COUNT(*) FROM POLICIES
UNION ALL SELECT 'CLAIMS',       COUNT(*) FROM CLAIMS
UNION ALL SELECT 'PAYMENTS',     COUNT(*) FROM PAYMENTS
UNION ALL SELECT 'ENDORSEMENTS', COUNT(*) FROM ENDORSEMENTS;


-- =====================================================================
-- PART A: The data quality issues listed in the assignment
-- =====================================================================

-- A1. Duplicates: is any claim_id used more than once?
-- Result: claim_id 1 appears twice.
SELECT CLAIM_ID, COUNT(*) AS times_found
FROM CLAIMS
GROUP BY CLAIM_ID
HAVING COUNT(*) > 1;

SELECT * FROM CLAIMS WHERE CLAIM_ID = '1';
-- Result: the second copy points to policy 999999, which doesn't exist.
-- Decision: keep the copy with the real policy; quarantine the other.


-- A2. Orphans: claims pointing to a policy that doesn't exist
-- Result: 1 row (the duplicate above).
SELECT c.*
FROM CLAIMS c
LEFT JOIN POLICIES p ON c.POLICY_ID = p.POLICY_ID
WHERE p.POLICY_ID IS NULL;


-- A3. Missing values: policies with no premium
-- Result: policy 6.
-- Decision: keep the policy and flag it; leave it out of loss-ratio math.
--           Filling in 0 would make its loss ratio meaningless.
SELECT * FROM POLICIES WHERE PREMIUM IS NULL;


-- A4. Negative amounts: payments below zero
-- Result: payment 11 = -500.00.
-- Decision: keep and flag it as a likely refund.
SELECT * FROM PAYMENTS WHERE PAYMENT_AMOUNT::NUMBER(12,2) < 0;


-- A5. Invalid dates: policies that expire before they start
-- Result: policy 21.
-- Decision: keep and flag it as an invalid term.
SELECT * FROM POLICIES WHERE EXPIRATION_DATE::DATE < EFFECTIVE_DATE::DATE;


-- =====================================================================
-- PART B: Clarifying questions raised with the business
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Endorsements: trust the amount's sign or the type?
-- Why asked: a "Coverage Increase" should add premium (positive) and a
--            reduction or cancellation should return premium (negative).
-- Result: every type is split roughly half positive, half negative,
--         so the sign follows no rule.
-- Decision: trust the type and set the sign from it; flag mismatches.
-- ---------------------------------------------------------------------
SELECT
    RAW_DATA:endorsement_type::STRING AS endorsement_type,
    CASE WHEN RAW_DATA:endorsement_amount::NUMBER(12,2) < 0 THEN 'negative' ELSE 'positive' END AS amount_sign,
    COUNT(*) AS endorsements
FROM ENDORSEMENTS
GROUP BY endorsement_type, amount_sign
ORDER BY endorsement_type, amount_sign;


-- ---------------------------------------------------------------------
-- Q2. Loss ratio: full premium or earned premium? Claim amount: final or estimate?
-- Why asked (claims): most claims are still Open or Pending, so their
--                     amounts are probably estimates that can change.
-- ---------------------------------------------------------------------
SELECT CLAIM_STATUS, COUNT(*) AS claims
FROM CLAIMS
GROUP BY CLAIM_STATUS;

-- Why asked (premium): many policies were still active when the data ends
-- (latest date in the data is 2026-05-25), so part of their premium isn't
-- "earned" yet.
-- Resolution: use claims / premium as the assignment defines it, and
--             document earned premium as a limitation.
SELECT COUNT(*) AS policies_still_active
FROM POLICIES
WHERE EXPIRATION_DATE::DATE > '2026-05-25';


-- ---------------------------------------------------------------------
-- Q3. Claims outside the policy's coverage dates: keep or exclude?
-- Why asked: a large share of claims fall outside their policy dates.
-- Result: ~60 before the policy starts, ~118 after it ends.
-- Decision: exclude claims BEFORE the start (no coverage existed yet);
--           keep claims AFTER the end (late reporting is normal).
--           Every claim stays in the data with a flag.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN c.CLAIM_DATE::DATE < p.EFFECTIVE_DATE::DATE  THEN 'before policy start'
        WHEN c.CLAIM_DATE::DATE > p.EXPIRATION_DATE::DATE THEN 'after policy end'
        ELSE 'during policy'
    END AS claim_timing,
    COUNT(*) AS claims,
    SUM(c.CLAIM_AMOUNT::NUMBER(12,2)) AS claim_amount
FROM CLAIMS c
JOIN POLICIES p ON c.POLICY_ID = p.POLICY_ID
WHERE p.EXPIRATION_DATE::DATE >= p.EFFECTIVE_DATE::DATE   -- skip policy 21 (invalid term)
GROUP BY claim_timing;

-- Total premium, for the loss-ratio comparison in the README:
--   all claims / premium              = ~0.88
--   excluding "before policy start"   = ~0.77   (chosen)
--   "during policy" only              = ~0.52
SELECT SUM(PREMIUM::NUMBER(12,2)) AS total_premium FROM POLICIES;


-- ---------------------------------------------------------------------
-- Q4. payments.csv: premium collected, or money paid out on claims?
-- Why asked: payments link to a policy, not a claim, and the totals
--            don't obviously match premium or claims.
-- ---------------------------------------------------------------------
SELECT
    (SELECT SUM(PREMIUM::NUMBER(12,2))        FROM POLICIES) AS total_premium,
    (SELECT SUM(PAYMENT_AMOUNT::NUMBER(12,2)) FROM PAYMENTS) AS total_payments,
    (SELECT SUM(CLAIM_AMOUNT::NUMBER(12,2))   FROM CLAIMS)   AS total_claims;

-- Clue: if payments were claim payouts, policies with no claims would have
-- no payments. Result: most paying policies have no claims at all, which
-- looks like premium installments.
-- Resolution: payments = premium collected from customers.
SELECT COUNT(DISTINCT pay.POLICY_ID) AS policies_with_payments_but_no_claims
FROM PAYMENTS pay
LEFT JOIN CLAIMS c ON pay.POLICY_ID = c.POLICY_ID
WHERE c.CLAIM_ID IS NULL;
