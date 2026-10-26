ALTER PROCEDURE [Payment].[SaveBillTransaction] 
@BillBookNo Nvarchar(20)=Null, 
@InvoiceNo  int=Null, 
@PaymentMode  nvarchar(max)=Null, 
@PaymentType  nvarchar(max)=Null, 
@DDChequeNo nvarchar(max)=NULL, 
@DDChequeDate Date =null, 
@BankName Nvarchar(max)=null, 
@PaymentResource nvarchar(max)=null, 
@BehalfPayerName nvarchar(max)=null, 
@MobileNo nvarchar(20)=null, 
@EmailID nvarchar(60)=null, 
@UserID int, 
@CFCID int, 
@Amount float, 
@MiscellaneousFee float=null, 
@UniqID nvarchar(max), 
@RefID nvarchar(max) =null, 
@Language nvarchar(max) = null 
AS  
BEGIN  
SET NOCOUNT ON; 
    DECLARE @msg NVARCHAR(100) = '' 
    DECLARE @tranDate DATETIME = GETDATE(); 
 
    DECLARE @AutoDownload INT 
    SELECT @AutoDownload = CAST(DefaultValue_Bit AS INT) 
    FROM Collective.ApplicationSetting 
    WHERE FlagName = 'AutoReceiptDownload' 
  
    ---Start last date logic as per assessment rule master 
    DECLARE @IsPenaltyMonthly INT 
    DECLARE @PenaltyDate DATETIME 
    SET @PenaltyDate = GETDATE() 
    SELECT @IsPenaltyMonthly = COALESCE(IsPenaltyMonthaly, 0) FROM AssessmentRulesMaster 
  
    IF @IsPenaltyMonthly = 1 
    BEGIN 
        SELECT @PenaltyDate = DATEADD(MONTH, DATEDIFF(MONTH, -1, GETDATE())-1, -1) 
    END 
    -- End last date logic 
 
    DECLARE @rowcount INT 
    DECLARE @StampMasterID INT 
    DECLARE @StampCount INT = 0 
    DECLARE @TinyURL NVARCHAR(MAX) 
 
    SET @rowcount = ISNULL((SELECT COUNT(OwnerID) FROM PropertyTax.TransactionDetails WITH (NOLOCK) WHERE ID = @UniqID), 0) 
 
    SELECT @TinyURL = DefaultValue_NVARCHAR 
    FROM Collective.ApplicationSetting 
    WHERE FlagName = 'ReciptDownloadWebUrlForSMS'

    -- ✅ Ward-wise BillBook Resolution OR 'Extended' for Cheque
    DECLARE @IsWardWiseBillBook BIT = 0
    DECLARE @ActualWardNo NVARCHAR(100)
    DECLARE @OwnerIDForBillBook INT
    DECLARE @NextInvoiceNo INT  -- holds computed InvoiceNo (max(InvoiceNo)+1), only set for online payments

    -- 1. If it's a Cheque, it starts as 'Inprocess' with 'Extended' BillBook
    IF @PaymentMode = 'Cheque'
    BEGIN
        SET @BillBookNo = 'Extended'
    END
    -- 2. Otherwise (Cash/DD/Online), resolve the actual ward-wise BillBook
    ELSE
    BEGIN
        -- Get IsWardWiseBillBook flag
        SELECT TOP 1 @IsWardWiseBillBook = ISNULL(DefaultValue_Bit, 0)
        FROM Collective.ApplicationSetting WITH (NOLOCK)
        WHERE FlagName = 'IsWardWiseBillBook'

        -- Safety net
        IF ISNULL(@IsWardWiseBillBook, 0) = 0
            SET @IsWardWiseBillBook = 1

        -- Get OwnerID from TransactionDetails
        SELECT TOP 1 @OwnerIDForBillBook = OwnerID
        FROM PropertyTax.TransactionDetails WITH (NOLOCK)
        WHERE ID = @UniqID

        IF ISNULL(@IsWardWiseBillBook, 0) = 1
        BEGIN
            DECLARE @TempBillBook NVARCHAR(20) = NULL
            IF ISNULL(@PaymentResource,'') = 'Offline'
            BEGIN
                SELECT TOP 1 @ActualWardNo = NewWardNo
                FROM PropertyMast WITH (NOLOCK)
                WHERE OwnerID = @OwnerIDForBillBook

                SELECT TOP 1 @TempBillBook = BillBookNo
                FROM Online.BillBookMaster WITH (NOLOCK)
                WHERE UserID = @UserID AND WardNo = @ActualWardNo

                IF @TempBillBook IS NOT NULL
                    SET @BillBookNo = @TempBillBook
            END
            ELSE
            BEGIN
                SELECT TOP 1 @ActualWardNo = NewWardNo
                FROM PropertyMast WITH (NOLOCK)
                WHERE OwnerID = @OwnerIDForBillBook

                SELECT TOP 1 @TempBillBook = ForOnlineWardNo
                FROM Online.OnlinePayBillbookWardDetails WITH (NOLOCK)
                WHERE ActualWardNo = @ActualWardNo

                -- Update parameter if mapping found
                IF @TempBillBook IS NOT NULL
                    SET @BillBookNo = @TempBillBook

                -- online payment only - compute next InvoiceNo as max(InvoiceNo)+1 scoped by resolved @BillBookNo
                IF EXISTS (SELECT TOP 1 InvoiceNo FROM dbo.BillTransactionDetails WITH (NOLOCK) WHERE BillBookNo = @BillBookNo)
                BEGIN
                    SELECT TOP 1 @NextInvoiceNo = ISNULL(InvoiceNo,0) + 1
                    FROM dbo.BillTransactionDetails WITH (NOLOCK)
                    WHERE BillBookNo = @BillBookNo
                    ORDER BY TransactionDate DESC
                END
                ELSE
                BEGIN
                    SET @NextInvoiceNo = 1
                END
            END
        END
    END

    -- Insert statements for procedure here 
    BEGIN TRANSACTION [TranBT] 
    BEGIN TRY 
    Try1: 
        BEGIN TRY 
            DECLARE @PaymentModeCode NVARCHAR(50) 
            DECLARE @CounterReceiptNo NVARCHAR(MAX) 
            DECLARE @GlobalReceiptNo NVARCHAR(MAX) 
            DECLARE @GlobalID INT 
            DECLARE @YearforGlobalID INT 
            DECLARE @FinanceYear INT 

            SET @FinanceYear = (SELECT MAX(FinanceYear) FROM TransYearMast) 
            SET @YearforGlobalID = (
                SELECT RIGHT(CAST(MAX(FinanceYear) AS VARCHAR(4)), 2) + 
                       RIGHT(CAST(MAX(FinanceYear)+1 AS VARCHAR(4)), 2) 
                FROM TransYearMast)  
   
            DECLARE @MerchantTxnRefNumber NVARCHAR(200); 
            SELECT TOP 1 @MerchantTxnRefNumber = MerchantTxnRefNumber  
            FROM PropertyTax.TransactionDetails WITH (NOLOCK) 
            WHERE ID = @UniqID 
   
            SET @PaymentModeCode = (
                SELECT ISNULL(PaymentModeCode,'00') 
                FROM Online.PaymentModeMaster 
                WHERE Mode = (@PaymentMode)) 
 
            SELECT @CounterReceiptNo = @BillBookNo + @PaymentModeCode + (
                CASE 
                    WHEN LEN(@InvoiceNo) = 1 THEN '00000' + CONVERT(NVARCHAR(10), @InvoiceNo) 
                    WHEN LEN(@InvoiceNo) = 2 THEN '0000' + CONVERT(NVARCHAR(10), @InvoiceNo) 
                    WHEN LEN(@InvoiceNo) = 3 THEN '000' + CONVERT(NVARCHAR(10), @InvoiceNo) 
                    WHEN LEN(@InvoiceNo) = 4 THEN '00' + CONVERT(NVARCHAR(10), @InvoiceNo) 
                    WHEN LEN(@InvoiceNo) = 5 THEN '0' + CONVERT(NVARCHAR(10), @InvoiceNo) 
                    ELSE CONVERT(NVARCHAR(10), @InvoiceNo) 
                END) 
 
            ;WITH cte AS (
                SELECT COALESCE(MAX(GlobalID), 0) AS GlobalID 
                FROM BillTransactionDetails 
                WHERE FinanceYear = @FinanceYear 
                UNION ALL 
                SELECT COALESCE(MAX(GlobalID), 0) 
                FROM Online.CollectionCancelation 
                WHERE FinanceYear = @FinanceYear
            ) 
            SELECT @GlobalID = COALESCE(MAX(GlobalID), 0) + 1 FROM cte
   
            SELECT @GlobalReceiptNo = CONVERT(NVARCHAR(MAX), @YearforGlobalID) + '0044' + (
                CASE 
                    WHEN LEN(@GlobalID) = 1 THEN '000000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 2 THEN '00000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 3 THEN '0000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 4 THEN '000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 5 THEN '00' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 6 THEN '0' + CONVERT(NVARCHAR(10), @GlobalID) 
                    ELSE CONVERT(NVARCHAR(10), @GlobalID) 
                END) 
   
            EXEC [Payment].[GenerateInvoiceNo] 
                @BillBookNo,
                @UserID,
                @MerchantTxnRefNumber,
                @PaymentModeCode,
                @UniqID,
                @FinanceYear 

            -- Get GlobalID from InvoiceGeneration to rebuild correct receipt no
            SELECT TOP 1 @GlobalID = GlobalID 
            FROM Payment.InvoiceGeneration WITH (NOLOCK) 
            WHERE UniqID = @UniqID 

            SET @GlobalReceiptNo = CONVERT(NVARCHAR(MAX), @YearforGlobalID) + '0044' + (
                CASE 
                    WHEN LEN(@GlobalID) = 1 THEN '000000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 2 THEN '00000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 3 THEN '0000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 4 THEN '000' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 5 THEN '00' + CONVERT(NVARCHAR(10), @GlobalID) 
                    WHEN LEN(@GlobalID) = 6 THEN '0' + CONVERT(NVARCHAR(10), @GlobalID) 
                    ELSE CONVERT(NVARCHAR(10), @GlobalID) 
                END)

        END TRY 
        BEGIN CATCH 
            INSERT INTO BillTransactionDetails_Error( 
                ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage,ErrorDate,RecordType) 
            SELECT   
                ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(),
                ERROR_PROCEDURE(),ERROR_LINE(),ERROR_MESSAGE(),
                GETDATE(),'BillTransaction' 
            SET @msg = 'Error :' + ERROR_MESSAGE() 
            WAITFOR DELAY '00:00:00.05' 
            GOTO Try1 
        END CATCH 
 
        IF NOT EXISTS (SELECT * FROM PropertyTax.TransactionDetails WITH (NOLOCK) WHERE ID = @UniqID) 
        BEGIN 
            IF (@Language = 'english') 
                SELECT N'Please search for the property again.' AS ErrMsg 
            ELSE IF (@Language = 'hindi') 
                SELECT N'कृपया संपत्ति को दोबारा खोजें।' AS ErrMsg 
            ELSE 
                SELECT N'कृपया मालमत्ता पुन्हा शोधा.' AS ErrMsg 
        END 

        IF EXISTS (
            SELECT * FROM BillTransactionDetails 
            WHERE OwnerID IN (
                SELECT TOP 1 OwnerID FROM PropertyTax.TransactionDetails WITH (NOLOCK) 
                WHERE ID = @UniqID) 
            AND TransactionDate >= DATEADD(MINUTE, -1, GETDATE()) 
            AND TaxTotal > 0) 
        BEGIN 
            IF (@Language = 'english') 
            BEGIN      
                SELECT N'The payment related to this property is already being processed. Please search property again.' AS ErrMsg 
                DELETE A FROM PropertyTax.TransactionDetails AS A WITH (NOLOCK) WHERE ID = @UniqID 
            END 
            ELSE IF (@Language = 'hindi') 
            BEGIN  
                SELECT N'इस संपत्ति से संबंधित भुगतान पहले से ही प्रक्रिया में है। कृपया संपत्ति को दोबारा खोजें।' AS ErrMsg 
                DELETE A FROM PropertyTax.TransactionDetails AS A WITH (NOLOCK) WHERE ID = @UniqID 
            END 
            ELSE 
            BEGIN 
                SELECT N'या मालमत्तेसंदर्भातील पेमेंट आधीच प्रक्रियेत आहे. कृपया मालमत्ता पुन्हा शोधा.' AS ErrMsg 
                DELETE A FROM PropertyTax.TransactionDetails AS A WITH (NOLOCK) WHERE ID = @UniqID  
            END 
        END 
        ELSE 
        BEGIN 
 
            INSERT INTO dbo.BillTransactionDetails 
            ( 
                OwnerID,BillBookNo,InvoiceNo,BillNo,TransactionDate,BillDate, 
                PropertyTax,Tax1,EducationTax,EmploymentTax,TreeCess,SpWaterCess,Sanitation, 
                DrainCess,RoadCess,FireCess,LightCess,WaterBenefit,MajorBuilding,SewageDisposalCess, 
                SpEducationTax,WaterBill,TaxTotal,Interest,Discount,Noticefee,WarrentFee,MiscellaneousFee, 
                NetTotal,EmpID,PaymentMode,DDChequeNo,PayeeName,BankName,BranchName,DDChequeDate,ExpiryDate, 
                IFSCNo,Amount,FinanceYear,PendingYear,Remark,PaymentType,Tax2,Tax3,Tax4,Tax5,UpdatedBy, 
                CreatedBy,CreatedDate,UpdatedDate,PaymentResource,DiscountPercentage, 
                ChequeStatus, 
                GrpOneInterestDiscount,GrpOneInterestDiscountPercentage, 
                RainWaterHarvestingDiscountAmount,RainWaterHarvestingDiscountPercentage, 
                EmailId,MobileNumber,LastDate,MerchantTxnRefNumber,GarbageSegregationDiscountAmount, 
                GarbageSegregationDiscountPercentage,GarbageDisposalDiscountAmount,GarbageDisposalDiscountPercentage, 
                SolarEnergyDiscountAmount,SolarEnergyDiscountPercentage,OtherFee,OtherFeeHeadName, 
                SpWaterCessDiscount,SpWaterCessDiscountPercentage,DrainCessDiscount,DrainCessDiscountPercentage,ReceiptCount, 
                Latitude,Longitude,PublicIP,LocalIP,LocalMac,Location,OnlineDiscountAmount,OnlineDiscountPercentage, 
                ChequeBounceFee,PaperFee,PaymentGetwayName, 
                SocietyPaymentID,BehalfPayerName,CashierUserID,ActiveYearID,AdharCardNumber,AppComplaintID, 
                TxnPaymentMode,DebitRefID,UserID,FamilyPlanningDiscountAmount,FamilyPlanningDiscountPercentage, 
                PramanPatraFee,Client_IP,Client_MAC,UniqueTokenID,TokenNo,CFCID,TaxPayerName,OccupierNameMarathi,NewPropertyDiscAmount, 
                NewPropertyDiscPercentage,OutWardNo,RemarkForDiffAmountCal, 
                WomenOwnerDiscountAmount,WomenDiscountPercentage,BillDistributionDisc,TreeSavardhanDiscount,TreeSavardhanDiscountPercentage, 
                VermiCompDiscount,VermiCompDiscountPercentage,SEGeneratorDiscount,SWHeaterDiscount,PhysicalDisabilityDiscount, 
                EPFChalanDiscount,RegularTaxPayerDiscount,IsPayFromSMSurl, 
                ZeroWestDiscount,ZeroWestDiscountPercentage,STPDiscount,STPDiscountPercentage,  
                OnlineCompostingDiscount,OnlineCompostingDiscountPercentage,FullPaidDiscount,FullPaidDiscountPercentage, 
                FreedomFighterDiscount, FreedomFighterDiscountPercentage,ExMilitrySoldierDiscount, ExMilitrySoldierDiscountPercentage, 
                UnMarriedMartyredSoldierDiscount,UnMarriedMartyredSoldierDiscountPercentage, GallantrySoldierDiscount,GallantrySoldierDiscountPercentage, 
                SelfAssessmentDiscount, SelfAssessmentDiscountPercentage,OnlineCompostingPlusSTPDiscount,OnlineCompostingPlusSTPDiscountPercentage, 
                ZeroWestPlusSTPDiscount,ZeroWestPlusSTPDiscountPercentage,ZeroWestPlusRainWaterDiscount,ZeroWestPlusRainWaterDiscountPercentage, 
                ZeroWestPlusSolarEnergyDiscountAmount, ZeroWestPlusSolarEnergyDiscountPercentage, 
                ZeroWestPlusRainWaterPlusSolarEnergyDiscountAmount, ZeroWestPlusRainWaterPlusSolarEnergyDiscountPercentage,
                CounterReceiptNo,GlobalID,GlobalReceiptNo,[StampCount], 
                [PropertyTaxInterest],[Tax1Interest],[EducationTaxInterest],[EmploymentTaxInterest],
                Tax5DiscountPercentage, ClearingDate
            ) 
            SELECT 
                OwnerID,
                @BillBookNo,
                ISNULL(@NextInvoiceNo, (SELECT InvoiceNo FROM [Payment].[InvoiceGeneration] WHERE UniqID = @UniqID)),
                ISNULL(BillNo,0),
                GETDATE() AS TransactionDate,
                BillDate, 
                PropertyTax,Tax1,EducationTax,EmploymentTax,TreeCess,SpWaterCess,Sanitation, 
                DrainCess,RoadCess,FireCess,LightCess,WaterBenefit,MajorBuilding,SewageDisposalCess, 
                SpEducationTax,WaterBill, 
                TaxTotal, 
                Interest,
                Discount,Noticefee,WarrentFee,
                (CASE WHEN PaymentType = 'current' THEN ISNULL(@MiscellaneousFee,0) 
                      WHEN PaymentType = 'Pending' AND @rowcount = 1 THEN ISNULL(@MiscellaneousFee,0) 
                      ELSE 0 
                 END), 
                ((ISNULL([NetTotal],0) + (CASE WHEN PaymentType = 'current' THEN ISNULL(@MiscellaneousFee,0) WHEN PaymentType = 'Pending' AND @rowcount = 1 THEN ISNULL(@MiscellaneousFee,0) ELSE 0 END))) 
                ,@UserID,@PaymentMode,@DDChequeNo,PayeeName,@BankName,BranchName,@DDChequeDate,ExpiryDate, 
                IFSCNo,(ISNULL(Amount,0) + ISNULL(@MiscellaneousFee,0)),FinanceYear,PendingYear,ISNULL(Remark,''),PaymentType,Tax2,Tax3,Tax4,Tax5,@UserID, 
                @UserID,@tranDate AS CreatedDate,UpdatedDate,@PaymentResource,DiscountPercentage, 
                (CASE WHEN @PaymentMode IN ('Cheque') THEN 'Inprocess' WHEN @PaymentMode IN ('DD') THEN 'Cleared' ELSE '' END),
                GrpOneInterestDiscount,GrpOneInterestDiscountPercentage, 
                RainWaterHarvestingDiscountAmount,RainWaterHarvestingDiscountPercentage, 
                @EmailId,LTRIM(RTRIM(STR(@MobileNo, 20, 0))) AS NVarcharColumn,@PenaltyDate AS LastDate,MerchantTxnRefNumber,GarbageSegregationDiscountAmount, 
                GarbageSegregationDiscountPercentage,GarbageDisposalDiscountAmount,GarbageDisposalDiscountPercentage, 
                SolarEnergyDiscountAmount,SolarEnergyDiscountPercentage,OtherFee,OtherFeeHeadName, 
                0,0,DrainCessDiscount,DrainCessDiscountPercentage,1, 
                Latitude,Longitude,PublicIP,LocalIP,LocalMac,Location,OnlineDiscountAmount,OnlineDiscountPercentage, 
                ChequeBounceFee,PaperFee,PaymentGetwayName, 
                SocietyPaymentID,@BehalfPayerName,@UserID,ActiveYearID,AdharCardNumber,AppComplaintID, 
                TxnPaymentMode,@RefID,@UserID,FamilyPlanningDiscountAmount,FamilyPlanningDiscountPercentage, 
                PramanPatraFee,'','','','',@CFCID,TaxPayerName,OccupierNameMarathi,NewPropertyDiscAmount, 
                NewPropertyDiscPercentage,'','', 
                WomenOwnerDiscountAmount,WomenDiscountPercentage,BillDistributionDisc,TreeSavardhanDiscount,TreeSavardhanDiscountPercentage, 
                VermiCompDiscount,VermiCompDiscountPercentage,SEGeneratorDiscount,SWHeaterDiscount,PhysicalDisabilityDiscount, 
                EPFChalanDiscount,RegularTaxPayerDiscount,IsPayFromSMSurl, 
                ZeroWestDiscount,ZeroWestDiscountPercentage,STPDiscount,STPDiscountPercentage,  
                OnlineCompostingDiscount,OnlineCompostingDiscountPercentage,FullPaidDiscount,FullPaidDiscountPercentage, 
                FreedomFighterDiscount, FreedomFighterDiscountPercentage,ExMilitrySoldierDiscount, ExMilitrySoldierDiscountPercentage, 
                UnMarriedMartyredSoldierDiscount,UnMarriedMartyredSoldierDiscountPercentage, GallantrySoldierDiscount,GallantrySoldierDiscountPercentage, 
                SelfAssessmentDiscount, SelfAssessmentDiscountPercentage,OnlineCompostingPlusSTPDiscount,OnlineCompostingPlusSTPDiscountPercentage, 
                ZeroWestPlusSTPDiscount,ZeroWestPlusSTPDiscountPercentage,ZeroWestPlusRainWaterDiscount,ZeroWestPlusRainWaterDiscountPercentage, 
                ZeroWestPlusSolarEnergyDiscountAmount, ZeroWestPlusSolarEnergyDiscountPercentage, 
                ZeroWestPlusRainWaterPlusSolarEnergyDiscountAmount, ZeroWestPlusRainWaterPlusSolarEnergyDiscountPercentage,
                (SELECT TOP 1 CounterReceiptNo FROM Payment.InvoiceGeneration WHERE UniqID = @UniqID) AS CounterReceiptNo, 
                (SELECT TOP 1 GlobalID FROM Payment.InvoiceGeneration WHERE UniqID = @UniqID) AS GlobalID, 
                @GlobalReceiptNo AS GlobalReceiptNo,
                @StampCount, 
                ISNULL([PropertyTaxInterest],0), 
                ISNULL([Tax1Interest],0), 
                ISNULL([EducationTaxInterest],0), 
                ISNULL([EmploymentTaxInterest],0), 
                ISNULL(Tax5DiscountPercentage,0),
                GETDATE() AS ClearingDate
            FROM PropertyTax.TransactionDetails WITH (NOLOCK) 
            WHERE ID = @UniqID 
     
            UPDATE A SET A.MobileNo = @MobileNo 
            FROM PropertyMast A WITH (NOLOCK) 
            WHERE A.OwnerID IN (SELECT TOP 1 ownerid FROM PropertyTax.TransactionDetails WITH (NOLOCK) WHERE ID = @UniqID) 
              AND ISNULL(MobileNo,'') = '' 

            PRINT 'ok1' 
            SET @msg = 'Success' 
        END 
    COMMIT TRANSACTION [TranBT] 
  
    IF @msg = 'Success' 
    BEGIN 
        SELECT TOP 1 
            MerchantTxnRefNumber,
            MobileNumber AS MobileNo,
            FORMAT(TransactionDate, 'MM/dd/yyyy hh:mm tt') AS CurrentDate, 
            CASE WHEN PaymentMode IN ('DD') THEN 'Cash' ELSE PaymentMode END AS PaymentMode,
            GlobalReceiptNo,
            Amount,
            OtherFeeHeadName,
            'Success' AS Message, 
            '' AS ErrMsg,
            @TinyURL AS TinyURL,
            @AutoDownload AS AutoDownload 
        FROM BillTransactionDetails 
        WHERE MerchantTxnRefNumber = (SELECT TOP 1 MerchantTxnRefNumber FROM PropertyTax.TransactionDetails WITH (NOLOCK) WHERE ID = @UniqID) 
        
        DELETE A FROM PropertyTax.TransactionDetails AS A WITH (NOLOCK) WHERE ID = @UniqID 
    END 
    END TRY 
    BEGIN CATCH 
        ROLLBACK TRANSACTION [TranBT] 
        INSERT INTO BillTransactionDetails_Error( 
            ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage,ErrorDate,RecordType) 
        SELECT   
            ERROR_NUMBER() AS ErrorNumber 
            ,ERROR_SEVERITY() AS ErrorSeverity 
            ,ERROR_STATE() AS ErrorState 
            ,ERROR_PROCEDURE() AS ErrorProcedure 
            ,ERROR_LINE() AS ErrorLine 
            ,ERROR_MESSAGE() AS ErrorMessage, 
            GETDATE() AS ErrorDate,'BillTransaction' 
        SET @msg = 'Error :' + ERROR_MESSAGE() 
 
        IF (ERROR_MESSAGE() LIKE '%BT_unique_transaction_data%') 
        BEGIN 
            SELECT TOP 1 
                MerchantTxnRefNumber,
                MobileNumber AS MobileNo,
                FORMAT(TransactionDate, 'MM/dd/yyyy hh:mm tt') AS CurrentDate, 
                CASE WHEN PaymentMode IN ('DD') THEN 'Cash' ELSE PaymentMode END AS PaymentMode,
                GlobalReceiptNo,
                Amount,
                OtherFeeHeadName,
                'Success' AS Message, 
                '' AS ErrMsg,
                @TinyURL AS TinyURL,
                @AutoDownload AS AutoDownload 
            FROM BillTransactionDetails 
            WHERE MerchantTxnRefNumber = (SELECT TOP 1 MerchantTxnRefNumber FROM PropertyTax.TransactionDetails WITH (NOLOCK) WHERE ID = @UniqID) 
            
            DELETE A FROM PropertyTax.TransactionDetails AS A WITH (NOLOCK) WHERE ID = @UniqID 
        END 
        ELSE 
        BEGIN 
            SELECT @msg AS ErrMsg, @msg AS Message 
        END 
    END CATCH 
END
