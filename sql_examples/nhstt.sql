----------------------------------------------------------------------
------------Figure A.1: Main outcome variables-------------------------
----------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW pathways AS
SELECT PathwayID
, MAX(Caseness_Flag) AS Caseness_Flag
, MAX(CompletedTreatment_Flag) AS CompletedTreatment_Flag
, MAX(Recovery_Flag) AS Recovery_Flag
, MAX(ReliableImprovement_Flag) AS ReliableImprovement_Flag
FROM ids101referral
--For this research, only consider pathways completing treatment during/before July 2024
WHERE Unique_MonthID < 1492 -- July 2024
GROUP BY PathwayID;

----------------------------------------------------------------------------
------------Figure A.2 and A.3: Therapy intensity variable---------------
----------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW pathway_intensities AS
WITH intensities AS (--derives the therapy intensity column for each care activity
SELECT i201.OrgID_Provider, i201.Unique_MonthID, i201.Person_ID, 
i201.PathwayID, i201.Unique_CareContactID, AppType, i201.CareContDate,

CASE WHEN CodeProcAndProcStatus IN ('1127281000000100','1129471000000105','842901000000108','286711000000107','314034001','449030000','933221000000107','1026131000000100','304891004','228557008','443730003') 
    THEN 1 -- High Intensity SNOMED codes
    WHEN CodeProcAndProcStatus IN ('748051000000105','748101000000105','748041000000107','748091000000102','748061000000108','702545008','1026111000000108','975131000000104') 
    THEN 0 -- Low Intensity SNOMED codes
    ELSE -1
END AS intensity

FROM ids201carecontact AS i201

LEFT JOIN ids202careactivity AS i202
ON i201.Unique_CareContactID = i202.Unique_CareContactID 
AND i201.PathwayID = i202.PathwayID

WHERE AppType IN ('01' ,'02', '03', '05') --assessment and/or treatment appointments only
AND AttendOrDNACode IN ('5', '6') --attended appointments only
ORDER BY PathwayID, CareContDate
),

care_contact_intensities AS (--derives the therapy intensity for each care contact
SELECT Unique_MonthID, Person_ID, PathwayID, Unique_CareContactID, AppType, CareContDate, MAX(intensity) AS intensity
FROM intensities
GROUP BY Unique_MonthID, Person_ID, PathwayID, Unique_CareContactID, AppType, CareContDate

UNION ALL

-- internet enabled therapy is considered to be low intensity
SELECT Unique_MonthID, Person_ID, PathwayID, StartDateIntEnabledTherLog AS Unique_CareContactID, 'Internet Enabled Therapy' AS AppType, StartDateIntEnabledTherLog AS CareContDate, 0 AS intensity

FROM ids205internetTherLog AS i205

GROUP BY Unique_MonthID, Person_ID, PathwayID, StartDateIntEnabledTherLog
)
pathway_contacts AS (

SELECT Person_ID, PathwayID

--counts the number of HI/LI contacts within a pathway
--only counts treatment contacts (excludes assessments)
, COUNT(DISTINCT CASE WHEN AppType NOT IN ('01') 
    THEN Unique_CareContactID ELSE null END) AS contacts
, COUNT(DISTINCT CASE WHEN intensity = 0 AND AppType NOT IN ('01') 
    THEN Unique_CareContactID ELSE null END) AS low_intensity_contacts
, COUNT(DISTINCT CASE WHEN intensity = 1 AND AppType NOT IN ('01') 
    THEN Unique_CareContactID ELSE null END) AS high_intensity_contacts
, COUNT(DISTINCT CASE WHEN intensity = -1 
    THEN Unique_CareContactID ELSE null END) AS other_contacts

--gets the initial assessment date
, MIN(CASE WHEN AppType IN ('01','03') THEN CareContDate ELSE null END) AS assessment_date
--earliest contact containing LI treatment
, MIN(CASE WHEN intensity = 0 THEN CareContDate ELSE null END) AS low_intensity_first_date
--earliest contact containing HI treatment
, MIN(CASE WHEN intensity = 1 THEN CareContDate ELSE null END) AS high_intensity_first_date
--gets the earliest care contact date overall
, MIN(CareContDate) AS first_contact

FROM care_contact_intensities

GROUP BY Person_ID, PathwayID
),
pathway_intensities AS (--assigns each care pathway to a therapy intensity
SELECT Person_ID, PathwayID,

--a "course of treatment" is considered to be 2 contacts or more
CASE --high intensity group
    WHEN high_intensity_contacts >= 2 AND low_intensity_contacts < 2 THEN 'high' 
    WHEN high_intensity_contacts >= 2 
        AND high_intensity_first_date <= low_intensity_first_date THEN 'high'
    --low intensity group
    WHEN low_intensity_contacts >= 2 AND high_intensity_contacts < 2 THEN 'low'
    --other groups / edge cases
    WHEN low_intensity_contacts >= 2 AND high_intensity_contacts >= 2 
        AND high_intensity_first_date > low_intensity_first_date THEN 'stepped'
    WHEN contacts < 2 THEN 'did not start treatment'
    WHEN high_intensity_contacts < 2 
        AND low_intensity_contacts < 2 THEN 'did not start treatment'
    ELSE 'unassigned'
END AS therapy_intensity

, contacts, low_intensity_contacts, high_intensity_contacts
, assessment_date, first_contact, low_intensity_first_date, high_intensity_first_date

FROM pathway_contacts
)
SELECT * FROM pathway_intensities;

----------------------------------------------------------------------
-------------Figure A.5: Initial scores-------------------------
--------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW initial_scores AS
SELECT get_date_from_UniqMonthID(Unique_MonthID) AS RecordStartDate, Unique_MonthID, OrgID_Provider, PathwayID, Person_ID, Unique_ServiceRequestID, ReferralRequestReceivedDate
, CompletedTreatment_Flag, Recovery_Flag, Caseness_Flag
--initial PHQ9 and GAD7 assessment scores
, ADSM, ADSM_FirstScore, PHQ9_FirstScore, GAD_FirstScore
--WSAS scores
, WASAS_HomeManagement_FirstScore, WASAS_PrivateLeisureActivities_FirstScore
, WASAS_Relationships_FirstScore, WASAS_SocialLeisureActivities_FirstScore
, WASAS_Work_FirstScore --sum all metrics to get total WSAS score
, WASAS_HomeManagement_FirstScore + WASAS_PrivateLeisureActivities_FirstScore + WASAS_Relationships_FirstScore + WASAS_SocialLeisureActivities_FirstScore + WASAS_Work_FirstScore AS WSAS_FirstScore
--presenting complaint (initial diagnosis)
, PresentingComplaintHigherCategory, PresentingComplaintLowerCategory, 
CASE WHEN PresentingComplaintLowerCategory IS null THEN PresentingComplaintHigherCategory
WHEN PresentingComplaintLowerCategory = 'Other F40-F43 code' THEN PresentingComplaintHigherCategory
ELSE PresentingComplaintLowerCategory END AS PresentingComplaint 

FROM ids101referral AS ids101
WHERE UsePathway_Flag = True;

----------------------------------------------------------------------
-------------Figure A.6: Last scores-----------------------------------
----------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW last_scores AS 
WITH monthly_records AS (
SELECT Unique_MonthID, PathwayID
--PHQ9 and GAD7 scores at final assessment
, ADSM_LastScore, PHQ9_LastScore, GAD_LastScore
--WSAS scores at final assessment
, WASAS_HomeManagement_LastScore, WASAS_PrivateLeisureActivities_LastScore
, WASAS_Relationships_LastScore, WASAS_SocialLeisureActivities_LastScore
, WASAS_Work_LastScore --sum all metrics to get total WSAS score
, WASAS_HomeManagement_LastScore + WASAS_PrivateLeisureActivities_LastScore + WASAS_Relationships_LastScore + WASAS_SocialLeisureActivities_LastScore + WASAS_Work_LastScore AS WSAS_LastScore
--row_num used to select the final record in the care pathway
, ROW_NUMBER() OVER (PARTITION BY PathwayID ORDER BY Unique_MonthID DESC) AS row_num
FROM ids101referral AS ids101

WHERE UsePathway_Flag = True
)
SELECT PathwayID, ADSM_LastScore, PHQ9_LastScore, GAD_LastScore
, WASAS_HomeManagement_LastScore, WASAS_PrivateLeisureActivities_LastScore
, WASAS_Relationships_LastScore, WASAS_SocialLeisureActivities_LastScore
, WASAS_Work_LastScore, WSAS_LastScore
FROM monthly_records
WHERE row_num = 1;

----------------------------------------------------------------------
---------------Figure A.7: Demographic and person-level predictors-------------
----------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW person_level_predictors AS 
SELECT Person_ID --demographic features
, MIN(Age_RP_StartDate) AS Age_ReferralRequest_ReceivedDate
, MAX(Gender) AS Gender
, MAX(GenderIdentity) AS GenderIdentity
, MAX(GenderIdentitySameAtBirth) AS GenderIdentitySameAtBirth
, MAX(IndicesOfDeprivationDecile) AS IndicesOfDeprivationDecile
, MAX(IndicesOfDeprivationQuartile) AS IndicesOfDeprivationQuartile
FROM ids001mpi AS ids001
GROUP BY Person_ID;

----------------------------------------------------------------------
-------------Figure A.8: Organisation-level predictors----------------
----------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW org_level_predictors AS
-- proportion of patients receiving high intensity therapy
WITH sessions_per_year AS (
SELECT OrgID_Provider,
-- size (sessions offered per year)
COUNT(DISTINCT Unique_CareContactID)/COUNT(DISTINCT Unique_MonthID)/12 AS sessions_per_year

FROM ids201carecontact 
GROUP BY OrgID_Provider
),
average_sessions_per_patient AS (--mean number of sessions offered to each patient
SELECT OrgID_Provider, 
SUM(sessions) / COUNT(DISTINCT Person_ID) AS average_sessions_per_patient

FROM (
SELECT OrgID_Provider, Person_ID, COUNT(DISTINCT Unique_CareContactID) AS sessions
FROM ids201carecontact 
GROUP BY OrgID_Provider, Person_ID
) 
GROUP BY OrgID_Provider
), 
proportion_stepped_up AS (--proportion of patients offered a "stepped up" care  pathway
SELECT OrgID_Provider, 
IFNULL(
    COUNT(DISTINCT CASE WHEN therapy_intensity = 'stepped' THEN i.PathwayID ELSE null END) 
    / COUNT(DISTINCT CASE WHEN therapy_intensity = 'stepped' OR therapy_intensity = 'low' THEN i.PathwayID ELSE null END)
, 0) AS proportion_stepped_up
FROM pathway_intensities AS i

LEFT JOIN ids101referral AS ids101 ON i.PathwayID = ids101.PathwayID
GROUP BY OrgID_Provider
),
high_low_sessions_per_year AS (
SELECT OrgID_Provider, 

COUNT(DISTINCT CASE WHEN intensity = 1 THEN Unique_careContactID ELSE null END) 
/ COUNT(DISTINCT Unique_monthID) / 12 AS high_intensity_sessions_per_year, 

COUNT(DISTINCT CASE WHEN intensity = 0 THEN Unique_careContactID ELSE null END) 
/ COUNT(DISTINCT Unique_monthID) / 12 AS low_intensity_sessions_per_year

FROM care_contact_intensities 
GROUP BY OrgID_Provider
)
SELECT a.*, b.sessions_per_year, c.proportion_stepped_up, high_intensity_sessions_per_year, low_intensity_sessions_per_year

FROM average_sessions_per_patient AS a

LEFT JOIN sessions_per_year AS b ON a.OrgID_Provider = b.OrgID_Provider

LEFT JOIN proportion_stepped_up c ON a.OrgID_Provider = c.OrgID_Provider

LEFT JOIN high_low_sessions_per_year d ON a.OrgID_Provider = d.OrgID_Provider;

--------------------------------------------------------------------------------------
--------------------Figure A.4: Final dataset with outcomes and predictors-----------------
-----------------------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW iapt_outcomes_and_predictors AS 
SELECT p.*, person.Age_ReferralRequest_ReceivedDate
, person.Gender, person.GenderIdentity, person.GenderIdentitySameAtBirth
, person.IndicesOfDeprivationDecile, person.IndicesOfDeprivationQuartile

, is.OrgID_Provider, is.ReferralRequestReceivedDate

, is.PresentingComplaintHigherCategory, is.PresentingComplaintLowerCategory

, is.ADSM, is.ADSM_FirstScore, is.PHQ9_FirstScore, is.GAD_FirstScore
, is.WASAS_HomeManagement_FirstScore, is.WASAS_PrivateLeisureActivities_FirstScore
, is.WASAS_Relationships_FirstScore, is.WASAS_SocialLeisureActivities_FirstScore
, is.WASAS_Work_FirstScore
, is.WASAS_HomeManagement_FirstScore + is.WASAS_PrivateLeisureActivities_FirstScore + is.WASAS_Relationships_FirstScore + is.WASAS_SocialLeisureActivities_FirstScore + is.WASAS_Work_FirstScore AS WSAS_FirstScore

, ls.ADSM_LastScore, ls.PHQ9_LastScore, ls.GAD_LastScore
, ls.WASAS_HomeManagement_LastScore, ls.WASAS_PrivateLeisureActivities_LastScore
, ls.WASAS_Relationships_LastScore, ls.WASAS_SocialLeisureActivities_LastScore
, ls.WASAS_Work_LastScore
, ls.WASAS_HomeManagement_LastScore + ls.WASAS_PrivateLeisureActivities_LastScore + ls.WASAS_Relationships_LastScore + ls.WASAS_SocialLeisureActivities_LastScore + ls.WASAS_Work_LastScore AS WSAS_LastScore
,
CASE WHEN PresentingComplaint = 'F411 - Generalised Anxiety Disorder' 
    THEN 'generalised_anxiety_disorder'
WHEN PresentingComplaint = 'Depression' THEN 'depression'
WHEN PresentingComplaint = 'F431 - Post-traumatic stress disorder' THEN 'PTSD'
WHEN PresentingComplaint = 'F401 - Social phobias' THEN 'social_anxiety'
WHEN PresentingComplaint = 'F410 - Panic disorder [episodic paroxysmal anxiety]' 
    THEN 'panic_disorder'
WHEN PresentingComplaint = 'F42 - Obsessive-compulsive disorder' THEN 'OCD'
WHEN PresentingComplaint = 'F452 Hypochondriacal Disorders' 
    THEN 'health_anxiety_hypochondriasis'
WHEN PresentingComplaint = 'F400 - Agoraphobia' THEN 'agoraphobia'
WHEN PresentingComplaint = '83482000 Body Dysmorphic Disorder' 
    THEN 'body_dysmorphic_disorder'
WHEN PresentingComplaint = 'F412 - Mixed anxiety and depressive disorder' 
    THEN 'mixed_anxiety_depression'
WHEN PresentingComplaint = 'F402 - Specific (isolated) phobias' THEN 'specific_phobias'
WHEN PresentingComplaint IS null OR PresentingComplaint = 'Invalid Data supplied' 
    OR PresentingComplaint = 'Unspecified' THEN null
ELSE 'other' END AS PresentingComplaint,

o.sessions_per_year, o.average_sessions_per_patient, o.proportion_stepped_up,
o.high_intensity_sessions_per_year, o.low_intensity_sessions_per_year

FROM pathway_intensities AS p

LEFT JOIN person_level_predictors AS person ON p.Person_ID = person.Person_ID
LEFT JOIN initial_scores AS is ON p.PathwayID = is.PathwayID
AND (
MONTH(p.first_contact) = MONTH(is.RecordStartDate) 
AND YEAR(p.first_contact) = YEAR(is.RecordStartDate)
)

LEFT JOIN last_scores AS ls ON p.PathwayID = ls.PathwayID
LEFT JOIN org_level_predictors AS o ON is.OrgID_Provider = o.OrgID_Provider;