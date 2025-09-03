------------------------------------------------------------------------------------------------------
--------Figure B.1: Flow Analytics - FTE Joiners, Leavers, Remainers and Stayers by Profession
-------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW flow_analytics AS
SELECT Time_Tm_End_Date, Fact_Unique_NHS_Identifier, Fact_Contracted_WTE
--current, previous and next profession
, profession, profession_From_Yearly_Working, profession_To_Yearly_Working
--current, previous and next occupation code
, Occ_Occupation_Code, Occ_Occupation_Code_From_Yearly_Working, Occ_Occupation_Code_To_Yearly_Working
--current, previous and next organisation
, Org_Ocs_Code, Org_Ocs_Code_From_Yearly_Working, Org_Ocs_Code_To_Yearly_Working

CASE WHEN Derived_Age_In_Years <= 54 THEN 'Under 55'
    WHEN Derived_Age_In_Years > 54 THEN '55+' ELSE '' END AS modAgeBand,

CASE WHEN Occ_Occupation_Code_From_Yearly_Working IS NULL 
    THEN Fact_Contracted_WTE ELSE 0 END AS joiner,

-- Newly Qualified Joiners to the NHS
CASE WHEN newly_qualified_check --derived field in earlier processing
    THEN Fact_Contracted_WTE ELSE 0 END AS joiner_NQ,

-- International Recruits
CASE WHEN NOT newly_qualified_check 
        AND international_recruit_check --derived field in earlier processing
                THEN Fact_Contracted_WTE ELSE 0 END AS joiner_IR,

-- Wider Labour Market joiners
CASE WHEN NOT newly_qualified_check AND NOT international_recruit_check
        AND Occ_Occupation_Code_From_Yearly_Working IS NULL 
        THEN Fact_Contracted_WTE ELSE 0 END AS joiner_WLM,

--staff who have remained in the same occupation
CASE WHEN profession_From_Yearly_Working = profession 
    THEN Fact_Contracted_WTE ELSE 0 END AS remainer,
CASE WHEN profession_To_Yearly_Working = profession 
    THEN Fact_Contracted_WTE ELSE 0 END AS stayer,

--staff joining an occupation/profession from within the NHS
CASE WHEN profession_From_Yearly_Working <> profession 
    AND profession_From_Yearly_Working IS NOT NULL 
    AND NOT newly_qualified_check AND NOT international_recruit_check
    THEN Fact_Contracted_WTE ELSE 0 
    END AS churn_joiner,
    
--staff leaving an occupation/profession staying within the NHS
CASE WHEN profession_To_Yearly_Working <> profession AND profession_To_Yearly_Working IS NOT NULL THEN Fact_Contracted_WTE ELSE 0 END AS churn_leaver,

--staff leaving the NHS
CASE WHEN Occ_Occupation_Code_To_Yearly_Working IS NULL 
    THEN Fact_Contracted_WTE ELSE 0 END AS leaver,
CASE WHEN Occ_Occupation_Code_To_Yearly_Working IS NULL AND modAgeBand = '55+' 
    THEN Fact_Contracted_WTE ELSE 0 END AS leaver55andOver,
CASE WHEN Occ_Occupation_Code_To_Yearly_Working IS NULL AND modAgeBand = 'Under 55' 
    THEN Fact_Contracted_WTE ELSE 0 END AS leaverUnder55

FROM vw_esr;

------------------------------------------------------------------------------------------------------------------------------------------------
----------------Figure B.2: Validation query ensuring that each NHS workforce joiner is counted once only, by checking--------------------------
-----------------------------consistency between the total Full-Time Equivalent (FTE) of joiners and the sum of all joiner subcategories-------
-------------------------------------------------------------------------------------------------------------------------------------------------
SELECT time_tm_end_date

--total FTE of joiners
, SUM(fact_contracted_wte) AS joiner_fte

--total FTE from the joiner fields
, sum(joiner_NQ + joiner_IR + joiner_WLM + churn_joiner) AS joiner_columns_sum

--check
--the total fte from the joiner fields should match the total FTE
, sum(joiner_NQ + joiner_IR + joiner_WLM + churn_joiner)=SUM(fact_contracted_wte) AS check

FROM flow_analytics

--filter to records who are classified as a joiner
WHERE (joiner_NQ > 0 OR joiner_IR > 0 OR joiner_WLM > 0 OR churn_joiner > 0)

GROUP BY time_tm_end_date
ORDER BY time_tm_end_date DESC

-------------------------------------------------------------------------------------------------------
----------------Figure B.3: Time series data aggregated by profession------------------------------
-------------------------------------------------------------------------------------------------------
SELECT Time_Tm_End_Date, profession, SUM(Fact_Contracted_WTE) AS fte
--FTE of staff joining the NHS
, SUM(joiner) AS joiners
, SUM(joiner_WLM) AS WLM
, SUM(joiner_NQ) AS NQ
, SUM(joiner_IR) AS IR
--FTE of staff remaining in their profession
, SUM(remainer) AS remainers
, SUM(stayer) AS stayers
--FTE of staff leaving the NHS
, SUM(leaver) AS leavers 
, SUM(leaver55andOver) AS leavers55andOver
, SUM(leaverUnder55) AS leaversUnder55
--FTE of staff remaining the NHS but changing profession
, SUM(churn_joiner) AS churn_joiners
, SUM(churn_leaver) AS churn_leavers

FROM flow_analytics 
-- Only consider FY end data when calculating flow rates 
WHERE Time_Tm_End_Date LIKE '%-03-31'

GROUP BY Time_Tm_End_Date, profession
ORDER BY profession, Time_Tm_End_Date DESC 