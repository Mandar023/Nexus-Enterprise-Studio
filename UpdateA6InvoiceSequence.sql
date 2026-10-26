-- =========================================================================
-- Script to align Ward A6 invoice numbers and receipt numbers 
-- with the printed PDF report sequence starting from 883.
-- Explicitly updates all IDs directly to prevent any shift duplicates/gaps.
-- =========================================================================

BEGIN TRAN;

-- =========================================================================
-- 1. Explicitly update BillTransactionDetails for all IDs:
-- =========================================================================
UPDATE BillTransactionDetails
SET CounterReceiptNo = LEFT(CounterReceiptNo, LEN(CounterReceiptNo) - 6) + 
                       CASE ID
                           WHEN 3225476 THEN '000883'
                           WHEN 3225477 THEN '000883'
                           WHEN 3224884 THEN '000884'
                           WHEN 3224885 THEN '000885'
                           WHEN 3224926 THEN '000886'
                           WHEN 3224927 THEN '000886'
                           WHEN 3225229 THEN '000887'
                           WHEN 3225389 THEN '000888'
                           WHEN 3225398 THEN '000889'
                           WHEN 3225403 THEN '000890'
                           WHEN 3225410 THEN '000891'
                           WHEN 3225415 THEN '000892'
                           WHEN 3225428 THEN '000893'
                           WHEN 3225429 THEN '000893'
                           WHEN 3225443 THEN '000894'
                           WHEN 3225444 THEN '000894'
                           WHEN 3225458 THEN '000895'
                           WHEN 3225466 THEN '000896'
                           WHEN 3225470 THEN '000897'
                           WHEN 3225752 THEN '000898'
                           WHEN 3225777 THEN '000899'
                           WHEN 3225840 THEN '000900'
                           WHEN 3226295 THEN '000901'
                           WHEN 3226532 THEN '000902'
                           WHEN 3226763 THEN '000903'
                           WHEN 3226764 THEN '000904'
                           WHEN 3226803 THEN '000905'
                           WHEN 3226855 THEN '000906'
                           WHEN 3227369 THEN '000907'
                           WHEN 3227592 THEN '000908'
                           WHEN 3228298 THEN '000909'
                           WHEN 3228299 THEN '000909'
                           WHEN 3228671 THEN '000910'
                           WHEN 3228769 THEN '000911'
                           WHEN 3228771 THEN '000912'
                           WHEN 3229854 THEN '000913'
                           WHEN 3230149 THEN '000914'
                           WHEN 3230365 THEN '000915'
                           WHEN 3230639 THEN '000916'
                           WHEN 3230769 THEN '000917'
                           WHEN 3230770 THEN '000917'
                           WHEN 3230777 THEN '000918'
                           WHEN 3230779 THEN '000919'
                           WHEN 3231183 THEN '000920'
                           WHEN 3231558 THEN '000921'
                           WHEN 3231559 THEN '000921'
                           WHEN 3231629 THEN '000922'
                           WHEN 3231653 THEN '000923'
                           WHEN 3231895 THEN '000924'
                           WHEN 3231896 THEN '000925'
                           WHEN 3231897 THEN '000926'
                           WHEN 3232152 THEN '000927'
                           WHEN 3232153 THEN '000927'
                           WHEN 3232195 THEN '000928'
                           WHEN 3232196 THEN '000929'
                           WHEN 3232214 THEN '000930'
                           WHEN 3232578 THEN '000931'
                           WHEN 3232595 THEN '000932'
                           WHEN 3232781 THEN '000933'
                           WHEN 3233166 THEN '000934'
                           WHEN 3233167 THEN '000934'
                           WHEN 3224886 THEN '000935'
                       END,
    InvoiceNo = CASE ID
                    WHEN 3225476 THEN 883
                    WHEN 3225477 THEN 883
                    WHEN 3224884 THEN 884
                    WHEN 3224885 THEN 885
                    WHEN 3224926 THEN 886
                    WHEN 3224927 THEN 886
                    WHEN 3225229 THEN 887
                    WHEN 3225389 THEN 888
                    WHEN 3225398 THEN 889
                    WHEN 3225403 THEN 890
                    WHEN 3225410 THEN 891
                    WHEN 3225415 THEN 892
                    WHEN 3225428 THEN 893
                    WHEN 3225429 THEN 893
                    WHEN 3225443 THEN 894
                    WHEN 3225444 THEN 894
                    WHEN 3225458 THEN 895
                    WHEN 3225466 THEN 896
                    WHEN 3225470 THEN 897
                    WHEN 3225752 THEN 898
                    WHEN 3225777 THEN 899
                    WHEN 3225840 THEN 900
                    WHEN 3226295 THEN 901
                    WHEN 3226532 THEN 902
                    WHEN 3226763 THEN 903
                    WHEN 3226764 THEN 904
                    WHEN 3226803 THEN 905
                    WHEN 3226855 THEN 906
                    WHEN 3227369 THEN 907
                    WHEN 3227592 THEN 908
                    WHEN 3228298 THEN 909
                    WHEN 3228299 THEN 909
                    WHEN 3228671 THEN 910
                    WHEN 3228769 THEN 911
                    WHEN 3228771 THEN 912
                    WHEN 3229854 THEN 913
                    WHEN 3230149 THEN 914
                    WHEN 3230365 THEN 915
                    WHEN 3230639 THEN 916
                    WHEN 3230769 THEN 917
                    WHEN 3230770 THEN 917
                    WHEN 3230777 THEN 918
                    WHEN 3230779 THEN 919
                    WHEN 3231183 THEN 920
                    WHEN 3231558 THEN 921
                    WHEN 3231559 THEN 921
                    WHEN 3231629 THEN 922
                    WHEN 3231653 THEN 923
                    WHEN 3231895 THEN 924
                    WHEN 3231896 THEN 925
                    WHEN 3231897 THEN 926
                    WHEN 3232152 THEN 927
                    WHEN 3232153 THEN 927
                    WHEN 3232195 THEN 928
                    WHEN 3232196 THEN 929
                    WHEN 3232214 THEN 930
                    WHEN 3232578 THEN 931
                    WHEN 3232595 THEN 932
                    WHEN 3232781 THEN 933
                    WHEN 3233166 THEN 934
                    WHEN 3233167 THEN 934
                    WHEN 3224886 THEN 935
                END
WHERE ID IN (
    3224926, 3224927, 3225229, 3225389, 3225398, 3225403, 3225410, 3225415,
    3225428, 3225429, 3225443, 3225444, 3225458, 3225466, 3225470, 3225476,
    3225477, 3224884, 3224885, 3225752, 3225777, 3225840, 3226295, 3226532,
    3226763, 3226764, 3226803, 3226855, 3227369, 3227592, 3228298, 3228299,
    3228671, 3228769, 3228771, 3229854, 3230149, 3230365, 3230639, 3230769,
    3230770, 3230777, 3230779, 3231183, 3231558, 3231559, 3231629, 3231653,
    3231895, 3231896, 3231897, 3232152, 3232153, 3232195, 3232196, 3232214,
    3232578, 3232595, 3232781, 3233166, 3233167, 3224886
);


-- =========================================================================
-- 2. Update Payment.InvoiceGeneration to keep it in sync:
-- =========================================================================
UPDATE IG
SET CounterReceiptNo = LEFT(IG.CounterReceiptNo, LEN(IG.CounterReceiptNo) - 6) + RIGHT('000000' + CAST(BTD.InvoiceNo AS VARCHAR(10)), 6),
    IG.InvoiceNo = BTD.InvoiceNo
FROM Payment.InvoiceGeneration IG
INNER JOIN PropertyTax.TransactionDetails TD ON TD.ID = IG.UniqID
INNER JOIN BillTransactionDetails BTD ON BTD.MerchantTxnRefNumber = TD.MerchantTxnRefNumber
WHERE BTD.ID IN (
    3224926, 3224927, 3225229, 3225389, 3225398, 3225403, 3225410, 3225415,
    3225428, 3225429, 3225443, 3225444, 3225458, 3225466, 3225470, 3225476,
    3225477, 3224884, 3224885, 3225752, 3225777, 3225840, 3226295, 3226532,
    3226763, 3226764, 3226803, 3226855, 3227369, 3227592, 3228298, 3228299,
    3228671, 3228769, 3228771, 3229854, 3230149, 3230365, 3230639, 3230769,
    3230770, 3230777, 3230779, 3231183, 3231558, 3231559, 3231629, 3231653,
    3231895, 3231896, 3231897, 3232152, 3232153, 3232195, 3232196, 3232214,
    3232578, 3232595, 3232781, 3233166, 3233167, 3224886
)
  AND IG.BillBookNo = 'JMCOP26A6';


-- =========================================================================
-- 3. Verification SELECT (Adjusted date filter to include July 30th)
-- =========================================================================
SELECT
    InvoiceNo,
    CounterReceiptNo,
    MerchantTxnRefNumber,
    TransactionDate,
    ID,
    OwnerID
FROM BillTransactionDetails BTD
INNER JOIN PropertyMast PM ON PM.OwnerID = BTD.OwnerID
WHERE BTD.TransactionDate >= '2026-06-29'
  AND BTD.TransactionDate < '2026-07-31'
  AND BTD.PaymentMode IN ('online','Upi','NetBanking','Card')
  AND PM.NewWardNo IN ('A6')
ORDER BY InvoiceNo;

-- Run COMMIT; if the SELECT results match.
-- Run ROLLBACK; if anything is wrong.
-- COMMIT;
-- ROLLBACK;
