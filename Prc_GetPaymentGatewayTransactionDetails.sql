ALTER   PROCEDURE [Payment].[Prc_GetPaymentGatewayTransactionDetails]  
@ID NVARCHAR(MAX)=NULL, 
@fromDate NVARCHAR(MAX) = NULL , 
@toDate NVARCHAR(MAX) = NULL , 
@status NVARCHAR(MAX) =NULL, 
@transactionID NVARCHAR(MAX) = NULL, 
@zoneNo NVARCHAR(MAX) = NULL, 
@wardNo NVARCHAR(MAX) = NULL, 
@propertyNo NVARCHAR(MAX) = NULL, 
@partitionNo NVARCHAR(MAX) = NULL, 
@Flag NVARCHAR(MAX) = NULL, 
@UserID INT = NULL 
AS 
BEGIN 
 IF(@Flag='GetAllTransactions') 
 BEGIN 
    
  IF OBJECT_ID('tempdb..#Temp_PGDATA') IS NOT NULL 
  BEGIN 
   DROP TABLE #Temp_PGDATA 
  END 
 
  SELECT (SELECT STRING_AGG(ID,',') FROM online.PaymentGatewayTransactionDetails AS B  
  WHERE MerchantTxnRefNumber=pg.MerchantTxnRefNumber) AS ID, p.OwnerID, NewWardNo AS Node_Sector,NewPropertyNo Building_No, 
  NewPartitionNo Property_No,MarathiOwnerName Owner_Name,  
  ISNULL(MarathiRenterName,'') Renter_Name,TxnStatus AS Status,ISNULL(MerchantTxnRefNumber,'') AS Merchant_Ref_Number, 
  ISNULL(PaymentResource,'') AS Payment_Resource,ISNULL(PaymentGetwayName,'') AS Gateway_Name,ISNULL(TxnPaymentMode, '') AS Resource, 
  BillBookNo BillBook_No,InvoiceNo Invoice_No,ISNULL(TxnID,'') TxnID ,ISNULL(Email,'') Email,MobileNumber, 
  (SELECT STRING_AGG(ISNULL(PaymentType,''),',') FROM online.PaymentGatewayTransactionDetails AS B  
  WHERE MerchantTxnRefNumber=pg.MerchantTxnRefNumber)  
  AS PaymentType, 
  FinanceYear AS FYear,CONVERT(NVARCHAR(MAX),TransactionDate, 103) AS Transaction_Date,CONVERT(INT,ISNULL(Amount,0)) [Amount],ISNULL(PaymentSource,'') 
  AS PaymentSource 
  INTO #Temp_PGDATA 
  FROM PropertyMast AS P INNER JOIN  
  ONLINE.PaymentGatewayTransactionDetails AS pg ON p.OwnerID=pg.OwnerID  
  INNER JOIN CombinedOwnerRenterNames AS c ON p.OwnerID=c.OwnerID   
  GROUP BY P.OwnerID,NewWardNo,NewPropertyNo,NewPartitionNo,MarathiOwnerName,MarathiRenterName,BillBookNo,InvoiceNo, 
  FinanceYear, TxnID,Email,MobileNumber,PaymentMode,PaymentResource,PaymentGetwayName,TxnPaymentMode,TxnStatus,MerchantTxnRefNumber,TransactionDate, 
  Amount,PaymentSource  

  IF(@fromDate !='' AND @toDate !='') 
  BEGIN 
   IF(@status = '') 
   BEGIN 
    SELECT * 
    FROM #Temp_PGDATA  WHERE Status ='Initiated' AND CONVERT(DATETIME, Transaction_Date,103) >= CONVERT(DATETIME, @fromDate,103)  
    AND CONVERT(DATETIME, Transaction_Date,103) <= CONVERT(DATETIME, @toDate,103) 
    ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
    RETURN; 
   END 
   ELSE 
   BEGIN 
    SELECT * 
    FROM #Temp_PGDATA  WHERE Status=@status AND CONVERT(DATETIME, Transaction_Date,103) >= CONVERT(DATETIME, @fromDate,103)  
    AND CONVERT(DATETIME, Transaction_Date,103) <= CONVERT(DATETIME, @toDate,103) 
    ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
    RETURN; 
   END 
  END 
 
  IF (@status !='') 
  BEGIN 
   SELECT TOP 200 * FROM #Temp_PGDATA  WHERE Status = @status ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
   RETURN; 
  END 
 
  IF (@transactionID !='') 
  BEGIN 
   SELECT * FROM #Temp_PGDATA WHERE Merchant_Ref_Number = @transactionID ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
   RETURN; 
  END 
 
  IF (@zoneNo !='' AND  @wardNo !='' AND @propertyNo = '') 
  BEGIN 
  IF(@status = '') BEGIN set @status='%' end 
   SELECT * FROM #Temp_PGDATA WHERE Node_Sector=@zoneNo+@wardNo and Status like @status ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
   RETURN; 
 
  END 
  IF (@zoneNo != '' AND (@wardNo = '' OR @wardNo IS NULL)) 
BEGIN 
IF (@status = '') SET @status = '%' 
 
SELECT * 
FROM #Temp_PGDATA 
WHERE LEFT(Node_Sector, 2) = @zoneNo 
AND Status LIKE @status 
ORDER BY CONVERT(DATETIME, Transaction_Date, 103) DESC 
RETURN 
END  
    
  IF (@zoneNo !='' AND  @wardNo !='' AND @propertyNo !='') 
  BEGIN 
  IF(@status = '') BEGIN set @status='%' end 
 
   SELECT * FROM #Temp_PGDATA WHERE Node_Sector=@zoneNo+@wardNo AND Building_No=ISNULL(@propertyNo,'')  
   AND Property_No=ISNULL(@partitionNo,'') and Status like @status  ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
   RETURN; 
  END 
  ELSE 
  BEGIN 
   SELECT TOP 50 * FROM #Temp_PGDATA  WHERE Status ='Initiated' ORDER BY CONVERT(DATETIME, Transaction_Date,103) DESC 
  END 
 END 
  
 ELSE IF (@Flag='GetTransactionForApprove') 
 BEGIN 
  SELECT OwnerID,MerchantTxnRefNumber AS MerchantTxnRefNumber,CAST(ISNULL(Amount, 0) AS INT) AS Amount, 
  CONVERT(VARCHAR,TransactionDate, 103)+' '+CONVERT(VARCHAR,TransactionDate, 108) AS TransactionDate, BillBookNo AS BillBookNo,InvoiceNo AS InvoiceNo, 
  ISNULL(PaymentMode,'') AS PaymentMode,isnull(PaymentResource,'') AS PaymentResource, 
  (SELECT top 1 DefaultValue_NVARCHAR FROM Collective.ApplicationSetting where FlagName='ReciptDownloadWebUrlForSMS') AS SMSURL 
  FROM online.PaymentGatewayTransactionDetails  
  WHERE ID IN (SELECT item FROM dbo.SplitString(@ID,','))  
  GROUP BY ID,OwnerID,MerchantTxnRefNumber,Amount,TransactionDate,BillBookNo,InvoiceNo,PaymentMode,PaymentResource  
 END 

 ELSE IF (@Flag='ApproveTransaction' OR @Flag='Approve') 
 BEGIN 
  -- 1. Update PaymentGatewayTransactionDetails to Success
  UPDATE Online.PaymentGatewayTransactionDetails 
  SET TxnID=@transactionID,
      TxnStatus='Success',
      UpdatedBy=@UserID, 
      UpdatedDate=GETDATE(), 
      ApprovedFrom = 'PaymentInitiatedScreen'  
  WHERE ID IN (SELECT item FROM dbo.SplitString(@ID,','))  
 
  -- 2. Update ClearingDate and TransactionId in BillTransactionDetails
  UPDATE btd 
  SET btd.ClearingDate=GETDATE(),
      btd.TransactionId=@transactionID,
      btd.ChequeStatus='Cleared'
  FROM dbo.BillTransactionDetails btd
  INNER JOIN Online.PaymentGatewayTransactionDetails pg ON btd.MerchantTxnRefNumber = pg.MerchantTxnRefNumber
  WHERE pg.ID IN (SELECT item FROM dbo.SplitString(@ID,','))

   SELECT 'Transaction Approved Successfully' AS Message , 1 AS Flag 
   RETURN; 
 END 
 
 ELSE IF (@Flag='DiscardTransaction') 
 BEGIN 
  UPDATE Online.PaymentGatewayTransactionDetails SET TxnID=@transactionID,TxnStatus='Failed',UpdatedBy=@UserID, 
  UpdatedDate=GETDATE(), 
  --UpdatedLatitude=0,UpdatedLongitude='',UpdatedPublicIP='',UpdatedLocalIP='',UpdatedLocalMac='', 
  ApprovedFrom = 'PaymentInitiatedScreen'  
  WHERE ID IN (SELECT item FROM dbo.SplitString(@ID,','))  
 
   SELECT 'Transaction Discarded Successfully' AS Message , 1 AS Flag 
   RETURN; 
 END 
 
 ELSE IF (@Flag='FillDashboardData') 
 BEGIN 
  CREATE TABLE #Temp_Zone(Zone NVARCHAR(MAX)) 
  IF ISNULL(@zoneNo,'')='' 
  BEGIN  
   INSERT INTO #Temp_Zone(Zone) 
   SELECT NodeName FROM online.NodeMaster 
  END 
  ELSE 
  BEGIN 
   INSERT INTO #Temp_Zone(Zone) 
   SELECT @zoneNo 
  END 
 
  IF OBJECT_ID('tempdb..#Temp_PGDashboard') IS Not NULL 
  BEGIN 
   DROP TABLE #Temp_PGDashboard 
  END 
 
  SELECT p.OwnerID,NewWardNo,NewPropertyNo,MerchantTxnRefNumber,TxnStatus,Amount 
  INTO #Temp_PGDashboard 
  FROM PropertyMast AS p  
  INNER JOIN ONLINE.PaymentGatewayTransactionDetails AS pg ON p.OwnerID=pg.OwnerID  
  --INNER JOIN #Temp_Zone AS Z WITH(NOLOCK) ON Z.Zone=SUBSTRING(P.NewWardNo,1,2) 
    INNER JOIN #Temp_Zone AS Z WITH(NOLOCK) ON Z.Zone=LEFT(p.NewWardNo,1)
  GROUP BY p.OwnerID,NewWardNo,NewPropertyNo,MerchantTxnRefNumber,TxnStatus,Amount 
    
      SELECT  
   (CASE WHEN @zoneNo = '' THEN 'All' ELSE @zoneNo END) AS Zone, 
   (SELECT ISNULL(COUNT(*),0) FROM #Temp_PGDashboard ) AS TotalTransactions, 
   (SELECT ISNULL(COUNT(*),0) FROM #Temp_PGDashboard WHERE TxnStatus ='Initiated') AS InprocessTransactions, 
      (SELECT ISNULL(COUNT(*),0) FROM #Temp_PGDashboard WITH(NOLOCK) WHERE TxnStatus = 'Success') AS SuccessTransactions, 
   (SELECT ISNULL(COUNT(*),0) FROM #Temp_PGDashboard WITH(NOLOCK) WHERE TxnStatus = 'Failed') AS FailedTransactions,    
COUNT(*) AS TotalCount 
 END 
   
END 
