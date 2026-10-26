USE [NTIS_4021]
GO
/****** Object:  StoredProcedure [Payment].[Prc_SaveDDChequeApproval]    Script Date: 8/19/2026 5:17:57 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER   PROCEDURE [Payment].[Prc_SaveDDChequeApproval]  
@MerchantTxnRefNumber nvarchar(max)=null, 
@OwnerID int=null, 
@BillBookNo nvarchar(max) = null, 
@InvoiceNo nvarchar(max) = null, 
--@FinanceYear int = null, 
@ChequeStatus  nvarchar(max) = null, 
@ExpiryDate datetime=null, 
@UpdatedBy nvarchar(100)=null, 
@UpdatedDate datetime=null, 
@Mode nvarchar(max), 
 
--@ChequeClearDate datetime=null 
 
@ChequeClearDate nvarchar(max)=null, 
@Remark nvarchar(max)='' 
AS 
BEGIN 
 
Declare @Amount float  
Declare @DDChequeNo nvarchar(max); 
Declare @StatusID nvarchar(10); 
DECLARE @PaymentType nvarchar(10); 

DECLARE @IsBillBookAllow nvarchar(20);
DECLARE @IsNewWardno nvarchar(20);

declare @FinanceYear int;
-- @FinanceYear used for tab payment only
 SELECT @FinanceYear = MAX(FinanceYear) 
    FROM TransYearMast

set @IsNewWardno=(select NewWardNo from PropertyMast where OwnerID=@OwnerID)
print '@IsNewWardno' print @IsNewWardno
print @IsNewWardno

-- Get PaymentResource from the transaction row to determine validation type
DECLARE @TxnPaymentResource NVARCHAR(MAX) = NULL;
SELECT TOP 1 @TxnPaymentResource = PaymentResource
FROM BillTransactionDetails WITH (NOLOCK)
WHERE MerchantTxnRefNumber = @MerchantTxnRefNumber 
  AND OwnerID = @OwnerID 
  AND PaymentMode IN ('Cheque', 'DD');

SET @IsBillBookAllow =
CASE
    -- For Tab payments, validate against tab.BillBookMaster
    WHEN LOWER(LTRIM(RTRIM(ISNULL(@TxnPaymentResource, '')))) = 'tab' THEN
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM tab.BillBookMaster 
                WHERE UserID = @UpdatedBy 
                  AND WardNo = @IsNewWardno 
                  AND FinanceYear = @FinanceYear 
                  AND Status = 1
            ) THEN 1
            ELSE 0
        END
    -- For Offline payments, validate against Online.BillBookMaster
    WHEN LOWER(LTRIM(RTRIM(ISNULL(@TxnPaymentResource, '')))) = 'offline' THEN
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Online.BillBookMaster 
                WHERE [Year] = 2026 
                  AND UserID = @UpdatedBy 
                  AND wardno = @IsNewWardno 
                  AND Status = 1
            ) THEN 1
            ELSE 0
        END
    -- For Online or other payments, cashier-specific billbook checks are not required
    ELSE 1
END;

 print '@IsBillBookAllow' print @IsBillBookAllow

 if @IsBillBookAllow = 1
 begin 
--set @ChequeClearDate=CONVERT(varchar, CAST(CONVERT(datetime, @ChequeClearDate, 103) AS datetime), 121)  
SET @ChequeClearDate =
    CAST(CONVERT(DATE, @ChequeClearDate, 103) AS DATETIME)
    + CAST(CONVERT(TIME, GETDATE()) AS DATETIME);
 
Select Top 1 @Amount=Amount,@DDChequeNo=DDChequeNo  
from BillTransactionDetails 
where MerchantTxnRefNumber= @MerchantTxnRefNumber and OwnerID=@OwnerID  
--and BillBookNo= @BillBookNo  
--and GlobalReceiptNo= @InvoiceNo  
and PaymentMode in ('Cheque', 'DD') 
 if exists (select 1  from BillTransactionDetails where  OwnerID=@OwnerID and MerchantTxnRefNumber = @MerchantTxnRefNumber and PaymentResource='Tab') 
  begin

	Update BillTransactionDetails 
	set ClearingDate = @ChequeClearDate, 
		TransactionDate = @ChequeClearDate   
	where MerchantTxnRefNumber = @MerchantTxnRefNumber 
	  and OwnerID = @OwnerID 
	  and PaymentMode in ('Cheque', 'DD') 
	 end
	 else
	 begin
	 -- ✅ CHANGED: Added TransactionDate = @ChequeClearDate to update both to the clearing date
	Update BillTransactionDetails 
	set ClearingDate = @ChequeClearDate, 
		TransactionDate = @ChequeClearDate,
		EmpID=@UpdatedBy
	where MerchantTxnRefNumber = @MerchantTxnRefNumber 
	  and OwnerID = @OwnerID 
	  and PaymentMode in ('Cheque', 'DD') 
 end

if @Mode='Cleared' 
Begin  
    -- ✅ 1. Resolve the BillBookNo: Offline=BillBookMaster / Online=Ward-wise  --prashant 05-07-26
    DECLARE @IsWardWiseBillBook BIT = 0
    DECLARE @ActualWardNo NVARCHAR(100) = NULL
    DECLARE @ResolvedBillBookNo NVARCHAR(20) = NULL
    DECLARE @TxnUserID INT = NULL
    DECLARE @TxnFinanceYear INT = NULL

    -- Get original cashier UserID (EmpID) and FinanceYear from the transaction row  --prashant 05-07-26
    SELECT TOP 1 
        @TxnUserID = EmpID,
        @TxnFinanceYear = FinanceYear
    FROM BillTransactionDetails WITH (NOLOCK)
    WHERE MerchantTxnRefNumber = @MerchantTxnRefNumber 
      AND OwnerID = @OwnerID 
      AND PaymentMode in ('Cheque', 'DD')

    SELECT TOP 1 @IsWardWiseBillBook = ISNULL(DefaultValue_Bit, 0)
    FROM Collective.ApplicationSetting WITH (NOLOCK)
    WHERE FlagName = 'IsWardWiseBillBook'

    IF ISNULL(@IsWardWiseBillBook, 0) = 0
        SET @IsWardWiseBillBook = 1

    IF ISNULL(@IsWardWiseBillBook, 0) = 1
    BEGIN
        SELECT TOP 1 @ActualWardNo = NewWardNo
        FROM PropertyMast WITH (NOLOCK)
        WHERE OwnerID = @OwnerID
		
  if exists (select 1  from BillTransactionDetails where  OwnerID=@OwnerID and MerchantTxnRefNumber = @MerchantTxnRefNumber and PaymentResource='Tab') 
	 Begin
	 
        IF LOWER(LTRIM(RTRIM(ISNULL(@TxnPaymentResource,'')))) = 'Tab'
        BEGIN
            -- Tab → billbook from Tab.BillBookMaster 
            SELECT TOP 1 @ResolvedBillBookNo = BillBookNo
            FROM tab.BillBookMaster WITH (NOLOCK)
            WHERE UserID = @TxnUserID AND WardNo = @ActualWardNo and FinanceYear=@FinanceYear
        END

	 End
	 Else
	 Begin
        IF LOWER(LTRIM(RTRIM(ISNULL(@TxnPaymentResource,'')))) = 'offline'
        BEGIN
            -- OFFLINE → billbook from Online.BillBookMaster (user + ward wise)  --prashant 05-07-26
            SELECT TOP 1 @ResolvedBillBookNo = BillBookNo
            FROM Online.BillBookMaster WITH (NOLOCK)
            WHERE UserID = @TxnUserID AND WardNo = @ActualWardNo
        END
        ELSE
        BEGIN
            -- ONLINE / other → ward-wise billbook from OnlinePayBillbookWardDetails
            SELECT TOP 1 @ResolvedBillBookNo = ForOnlineWardNo
            FROM Online.OnlinePayBillbookWardDetails WITH (NOLOCK)
            WHERE ActualWardNo = @ActualWardNo
        END
	 End
    END

    -- Fallback if no mapping found
    IF @ResolvedBillBookNo IS NULL
    BEGIN
        SET @ResolvedBillBookNo = @BillBookNo
    END

    PRINT 'TxnPaymentResource: ' + ISNULL(@TxnPaymentResource, 'NULL')
    PRINT 'TxnUserID: ' + ISNULL(CAST(@TxnUserID AS VARCHAR), 'NULL')
    PRINT 'ActualWardNo: ' + ISNULL(@ActualWardNo, 'NULL')
    PRINT 'ResolvedBillBookNo: ' + ISNULL(@ResolvedBillBookNo, 'NULL')

    -- ✅ 2. Find MAX InvoiceNo already used against the RESOLVED BillBookNo
    --    (same "find max, +1" pattern SaveBillTransaction relies on via
    --    Payment.GenerateInvoiceNo) and generate the next InvoiceNo for it.
    DECLARE @PaymentModeCode NVARCHAR(50) = '00'
    DECLARE @TxnInvoiceNo INT = NULL          -- original invoice no (under 'Extended')
    DECLARE @NewInvoiceNo INT = NULL          -- newly generated invoice no for resolved billbook
    DECLARE @PaddedInvoiceNo NVARCHAR(50) = ''
    DECLARE @NewCounterReceiptNo NVARCHAR(MAX) = NULL
    DECLARE @ExistingGlobalID INT = NULL
    DECLARE @ExistingGlobalReceiptNo NVARCHAR(MAX) = NULL

    -- Retrieve original InvoiceNo, PaymentModeCode, GlobalID/GlobalReceiptNo
    -- (GlobalID/GlobalReceiptNo stay as originally assigned — only the
    -- BillBookNo-scoped InvoiceNo + CounterReceiptNo are being re-resolved)
    SELECT TOP 1 
        @TxnInvoiceNo = InvoiceNo,
        @PaymentModeCode = ISNULL(PMM.PaymentModeCode, '00'),
        @ExistingGlobalID = BT.GlobalID,
        @ExistingGlobalReceiptNo = BT.GlobalReceiptNo
    FROM BillTransactionDetails BT WITH (NOLOCK)
    LEFT JOIN Online.PaymentModeMaster PMM WITH (NOLOCK) 
        ON PMM.Mode = BT.PaymentMode
    WHERE BT.MerchantTxnRefNumber = @MerchantTxnRefNumber 
      AND BT.OwnerID = @OwnerID 
      AND BT.PaymentMode in ('Cheque', 'DD')

    -- Find MAX InvoiceNo already issued for this resolved BillBookNo
    -- (checked across both InvoiceGeneration and BillTransactionDetails,
    -- same defensive double-check style SaveBillTransaction uses for GlobalID)
    ;WITH cte AS (
        SELECT COALESCE(MAX(InvoiceNo), 0) AS InvoiceNo
        FROM Payment.InvoiceGeneration WITH (NOLOCK)
        WHERE BillBookNo = @ResolvedBillBookNo
        UNION ALL
        SELECT COALESCE(MAX(InvoiceNo), 0)
        FROM BillTransactionDetails WITH (NOLOCK)
        WHERE BillBookNo = @ResolvedBillBookNo
    )
    SELECT @NewInvoiceNo = COALESCE(MAX(InvoiceNo), 0) + 1 FROM cte

    -- Pad new InvoiceNo (same padding rule used elsewhere for CounterReceiptNo)
    SET @PaddedInvoiceNo = 
        CASE 
            WHEN LEN(@NewInvoiceNo) = 1 THEN '00000' + CONVERT(NVARCHAR(10), @NewInvoiceNo) 
            WHEN LEN(@NewInvoiceNo) = 2 THEN '0000' + CONVERT(NVARCHAR(10), @NewInvoiceNo) 
            WHEN LEN(@NewInvoiceNo) = 3 THEN '000' + CONVERT(NVARCHAR(10), @NewInvoiceNo) 
            WHEN LEN(@NewInvoiceNo) = 4 THEN '00' + CONVERT(NVARCHAR(10), @NewInvoiceNo) 
            WHEN LEN(@NewInvoiceNo) = 5 THEN '0' + CONVERT(NVARCHAR(10), @NewInvoiceNo) 
            ELSE CONVERT(NVARCHAR(10), @NewInvoiceNo) 
        END

    -- Form new CounterReceiptNo using the resolved BillBookNo + new InvoiceNo (e.g. JMCOP25D1000465)
    SET @NewCounterReceiptNo = @ResolvedBillBookNo + @PaymentModeCode + @PaddedInvoiceNo

    PRINT 'TxnInvoiceNo (old/Extended): ' + ISNULL(CAST(@TxnInvoiceNo AS VARCHAR), 'NULL')
    PRINT 'NewInvoiceNo (resolved billbook): ' + ISNULL(CAST(@NewInvoiceNo AS VARCHAR), 'NULL')
    PRINT 'NewCounterReceiptNo: ' + ISNULL(@NewCounterReceiptNo, 'NULL')

    -- ✅ 3. Insert a NEW row into Payment.InvoiceGeneration for this cheque's
    --    clearance — with the resolved BillBookNo and newly generated
    --    InvoiceNo — instead of just updating the old 'Extended' row.
    --    NOTE: verify these column names against your actual
    --    Payment.InvoiceGeneration schema before running in prod.


    INSERT INTO Payment.InvoiceGeneration
        (UserID, BillBookNo, InvoiceNo, MerchantTxnRefNumber, PaymentMode, CounterReceiptNo, UniqID, FinanceYear, GlobalID,GlobalReceiptNo)
    VALUES
        (@UpdatedBy, @ResolvedBillBookNo, @NewInvoiceNo, @MerchantTxnRefNumber, 'Cheque', '', @ExistingGlobalID,2026 , '','')

    -- ✅ 4. Update the BillBookNo, InvoiceNo and CounterReceiptNo in BillTransactionDetails
    UPDATE BillTransactionDetails 
    SET 
        BillBookNo = @ResolvedBillBookNo,
        InvoiceNo = @NewInvoiceNo,
        CounterReceiptNo = @NewCounterReceiptNo

    WHERE MerchantTxnRefNumber = @MerchantTxnRefNumber 
      AND OwnerID = @OwnerID 
      AND PaymentMode in ('Cheque', 'DD')

    ----ALTER TABLE Online.DDChequeTransactionHistory ADD CFCID INT NULL 
    --------------------------------1st Step----------------------------- 
 if exists (select 1  from BillTransactionDetails where MerchantTxnRefNumber= @MerchantTxnRefNumber and OwnerID=@OwnerID and PaymentResource='Tab') 
	begin
    Insert into Online.DDChequeTransactionHistory(OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, ChequeStatus,CreatedDate,ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID) 
    select top(1) OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, @ChequeStatus, GETDATE() as CreatedDate,@ChequeClearDate as ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID from BillTransactionDetails 
    Where MerchantTxnRefNumber = @MerchantTxnRefNumber and OwnerID=@OwnerID and  
    --BillBookNo=@BillBookNo and  
    --Isnull(GlobalReceiptNo,0)=@InvoiceNo and  
    PaymentMode in ('Cheque', 'DD') 
 
    --------------------------------2nd Step----------------------------- 
    update BillTransactionDetails set  
     
    UpdatedDate=@UpdatedDate,  
    ChequeStatus=@ChequeStatus, 
    ExpiryDate=@ExpiryDate  
    where MerchantTxnRefNumber= @MerchantTxnRefNumber and  
    OwnerID=@OwnerID --and  
    --BillBookNo= @BillBookNo and  
    --isnull(GlobalReceiptNo,0)= @InvoiceNo  
    --FinanceYear= @FinanceYear  
    and PaymentMode in ('Cheque', 'DD') 
	end
	else
	begin
    Insert into Online.DDChequeTransactionHistory(OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, ChequeStatus, CreatedBy, CreatedDate,ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID) 
    select top(1) OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, @ChequeStatus, @UpdatedBy,GETDATE() as CreatedDate,@ChequeClearDate as ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID from BillTransactionDetails 
    Where MerchantTxnRefNumber = @MerchantTxnRefNumber and OwnerID=@OwnerID and  
    --BillBookNo=@BillBookNo and  
    --Isnull(GlobalReceiptNo,0)=@InvoiceNo and  
    PaymentMode in ('Cheque', 'DD') 
 
    --------------------------------2nd Step----------------------------- 
    update BillTransactionDetails set  
    UpdatedBy=@UpdatedBy,  
    UpdatedDate=@UpdatedDate,  
    ChequeStatus=@ChequeStatus, 
    ExpiryDate=@ExpiryDate  
    where MerchantTxnRefNumber= @MerchantTxnRefNumber and  
    OwnerID=@OwnerID --and  
    --BillBookNo= @BillBookNo and  
    --isnull(GlobalReceiptNo,0)= @InvoiceNo  
    --FinanceYear= @FinanceYear  
    and PaymentMode in ('Cheque', 'DD') 
	
	end

END  
 
 
if @Mode='NotCleared' 
Begin  
    --------------------------------1st Step----------------------------- 
    --alter table Online.DDChequeTransactionHistory add Remark nvarchar(max) null 
    Insert into Online.DDChequeTransactionHistory(OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, ChequeStatus, CreatedBy, CreatedDate,ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID,Remark) 
    select top(1) OwnerID, BillBookNo, InvoiceNo, TransactionDate, DDChequeNo, DDChequeDate,BankName,PaymentResource ,FinanceYear, Amount, MerchantTxnRefNumber, @ChequeStatus, @UpdatedBy,GETDATE() as CreatedDate,@ChequeClearDate as ChequeClearDate,GlobalReceiptNo,CounterReceiptNo,GlobalID,CFCID,@Remark from BillTransactionDetails 
    Where MerchantTxnRefNumber=@MerchantTxnRefNumber and OwnerID=@OwnerID 
    --and BillBookNo=@BillBookNo  
    --and Isnull(GlobalReceiptNo,0)=@InvoiceNo  
    --FinanceYear, 
    --and FinanceYear=@FinanceYear  
    and PaymentMode in ('Cheque', 'DD') 
 
    --------------------------------2nd Step----------------------------- 
    Update BillTransactionDetails  
    set UpdatedBy=@UpdatedBy, 
    UpdatedDate=@UpdatedDate,  
    ChequeStatus=@ChequeStatus, 
    ExpiryDate= @ExpiryDate  
    where  
    MerchantTxnRefNumber=@MerchantTxnRefNumber  
    and OwnerID=@OwnerID 
    --and BillBookNo=@BillBookNo  
    --and Isnull(GlobalReceiptNo,0)= @InvoiceNo  
    --and FinanceYear=@FinanceYear  
    and PaymentMode in ('Cheque', 'DD') 
 
    INSERT INTO [dbo].[BillTransactionDetails_Replica] 
    ([OwnerID] ,[BillBookNo] ,[InvoiceNo] ,[BillNo] ,[TransactionDate] ,[BillDate] ,[PropertyTax] ,[Tax1] ,[EducationTax] ,[EmploymentTax] ,[TreeCess] ,[SpWaterCess] ,[Sanitation] ,[DrainCess] ,[RoadCess] ,[FireCess] ,[LightCess] ,[WaterBenefit] ,[MajorBuilding] ,[SewageDisposalCess] ,[SpEducationTax] ,[WaterBill] ,[TaxTotal] ,[Interest] ,[Discount] ,[Noticefee] ,[WarrentFee] ,[NetTotal] ,[EmpID] ,[PaymentMode] ,[PaymentType] ,[DDChequeNo] ,[PayeeName] ,[BankName] ,[BranchName] ,[DDChequeDate] ,[ExpiryDate] ,[IFSCNo] ,[Amount] ,[FinanceYear] ,[PendingYear] ,[Remark] ,[Tax2] ,[Tax3] ,[Tax4] ,[Tax5] ,[UpdatedBy] ,[CreatedBy] ,[CreatedDate] ,[UpdatedDate] ,[PaymentResource] ,[MerchantTxnRefNumber] ,[ActiveYearID] ,[TransactionId] ,[EmailId] ,[MobileNumber] ,[AdharCardNumber] ,[DebitRefID] ,[MiscellaneousFee] ,[ChequeStatus] ,[DiscountPercentage] ,[RelID] ,[ISUpdateInNTIS] ,[DBCreatedBy] ,[DBUpdatedBy] ,[TaxType] ,[GrpOneInterestDiscount] ,[GrpOneInterestDiscountPercentage] ,[GrpTwoInterestDiscount] ,[GrpTwoInterestDiscountPercentage] ,[CalFixedPendingInterestDiscountPercentage] ,[RainWaterHarvestingDiscountAmount] ,[RainWaterHarvestingDiscountPercentage] ,[ManageID] ,[DeletedBy] ,[Latitude] ,[Longitude] ,[PublicIP] ,[LocalIP] ,[LocalMac]) 
         select [OwnerID] ,[BillBookNo] ,[InvoiceNo] ,[BillNo] ,[TransactionDate] ,[BillDate] ,[PropertyTax] ,[Tax1] ,[EducationTax] ,[EmploymentTax] ,[TreeCess] ,[SpWaterCess] ,[Sanitation] ,[DrainCess] ,[RoadCess] ,[FireCess] ,[LightCess] ,[WaterBenefit] ,[MajorBuilding] ,[SewageDisposalCess] ,[SpEducationTax] ,[WaterBill] ,[TaxTotal] ,[Interest] ,[Discount] ,[Noticefee] ,[WarrentFee] ,[NetTotal] ,[EmpID] ,[PaymentMode] ,[PaymentType] ,[DDChequeNo] ,[PayeeName] ,[BankName] ,[BranchName] ,[DDChequeDate] ,[ExpiryDate] ,[IFSCNo] ,[Amount] ,[FinanceYear] ,[PendingYear] ,@Remark ,[Tax2] ,[Tax3] ,[Tax4] ,[Tax5] ,[UpdatedBy] ,[CreatedBy] ,[CreatedDate] ,[UpdatedDate] ,[PaymentResource] ,[MerchantTxnRefNumber] ,[ActiveYearID] ,[TransactionId] ,[EmailId] ,[MobileNumber] ,[AdharCardNumber] ,[DebitRefID] ,[MiscellaneousFee] ,[ChequeStatus] ,[DiscountPercentage] ,[RelID] ,[ISUpdateInNTIS] ,[DBCreatedBy] ,[DBUpdatedBy] ,[TaxType] ,[GrpOneInterestDiscount] ,[GrpOneInterestDiscountPercentage] ,[GrpTwoInterestDiscount] ,[GrpTwoInterestDiscountPercentage] ,[CalFixedPendingInterestDiscountPercentage] ,[RainWaterHarvestingDiscountAmount] ,[RainWaterHarvestingDiscountPercentage] ,[ManageID] ,'' ,[Latitude] ,[Longitude] ,[PublicIP] ,[LocalIP] ,[LocalMac] from 
         BillTransactionDetails where MerchantTxnRefNumber=@MerchantTxnRefNumber and OwnerID=@OwnerID 
 
 
    Delete BillTransactionDetails where  
    MerchantTxnRefNumber=@MerchantTxnRefNumber and OwnerID=@OwnerID 
    --and BillBookNo=@BillBookNo  
    --and Isnull(GlobalReceiptNo,0)=@InvoiceNo  
    --and FinanceYear=@FinanceYear  
    and PaymentMode in ('Cheque', 'DD') 
End 
 
if @Mode='Cleared' 
Begin 
Select distinct PM.EmailID,PM.MobileNo as MobileNumber,MerchantTxnRefNumber,PaymentResource,'Cheque Clear' as TemplateName, 
(select DefaultValue_NVARCHAR from Collective.ApplicationSetting where FlagName='ReciptDownloadWebUrlForSMS') as URl,DDChequeNo,InvoiceNo,Amount,1 AS ChequeApprovalStatus,isnull(MarathiOwnerPrathamNav,'') as OwnerName from PropertyMast PM Inner Join BillTransactionDetails BT on PM.OwnerID=BT.OwnerID where MerchantTxnRefNumber=@MerchantTxnRefNumber 
END 
 
if @Mode='NotCleared' 
Begin 
Select distinct PM.EmailID,PM.MobileNo as MobileNumber,MerchantTxnRefNumber,PaymentResource,'Cheque Not Clear' as TemplateName, 
(select DefaultValue_NVARCHAR from Collective.ApplicationSetting where FlagName='ReciptDownloadWebUrlForSMS') as URl,DDChequeNo,InvoiceNo,Amount,DDChequeDate,BankName,GETDATE() AS ExpiryDate, 
(select isnull(DefaultValue_INT,0) from Collective.ApplicationSetting where FlagName='ChequeBounceFee') as ChequeBounceFee ,isnull(MarathiOwnerPrathamNav,'') as OwnerName from PropertyMast PM Inner Join Online.DDChequeTransactionHistory BT on PM.OwnerID=BT.OwnerID where MerchantTxnRefNumber=@MerchantTxnRefNumber 
END 
end
ELSE
    BEGIN 
        SELECT 10 AS ChequeApprovalStatus 
    END 
END
