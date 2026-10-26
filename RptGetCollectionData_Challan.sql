ALTER   PROCEDURE [Online].[RptGetCollectionData_Challan]
@NewWardNo nvarchar(Max)=null,
@NewFromPropertyNo	nvarchar(30)=null,
@NewToPropertyNo	nvarchar(30)=null,
@PaymentMode nvarchar(50)=null, 
@FinanceYear int=null,
@EmpID nvarchar(Max) = 0,
@TabEmpID nvarchar(Max)=null,
@PaymentResource nvarchar(30)=null,
@FromTransactionDate datetime=null,
@ToTransactionDate datetime=null,
@ZoneSectionNo		nvarchar(10)=null,
@PrintedBy nvarchar(max) =100,
@TaxType nvarchar(max)=null,
@SequenceMode nvarchar(max)=null
AS
BEGIN

/*set @DtlSummMode=ISNULL(@DtlSummMode,1)*/
Declare @TempEmpID nvarchar(Max)=null
create table #TempTblEmp
(
empid int
)




Declare @PrintedName NVARCHAR(MAX)
select @PrintedName=MAX(Name) from UserModule.UserMaster where UserID=ISNULL(@PrintedBy,'')

  --select @PrintedName

if @PaymentResource like '%NTIS%'
begin
	Set @PaymentResource = @PaymentResource + ',NTISPosting'
end

IF @EmpID = '0'
BEGIN 
delete from #TempTblEmp
set @EmpID=@EmpID+',0,1'
insert into #TempTblEmp
SELECT UserID FROM UserModule.UserMaster
insert into #TempTblEmp
SELECT '0'

if(@PaymentResource like '%nti%')
	begin
	insert into #TempTblEmp
	SELECT Distinct EmpID FROM BillTransactionDetails where PaymentResource in ('NTIS','NTISPosting','') and EmpID not in (SELECT empid FROM #TempTblEmp) 
	end
END
ELSE
BEGIN

delete from #TempTblEmp
if(@PaymentResource like '%nti%')
	begin
	select @TempEmpID= STUFF((SELECT Distinct ',' + Convert(nvarchar (Max),EmpID) FROM BillTransactionDetails where PaymentResource in ('NTIS','NTISPosting','') FOR XML PATH('')), 1, 1, '') 
	set @EmpID=@EmpID+',0,'+@TempEmpID
	end
else
	begin
		set @EmpID=@EmpID+',0'
	end

insert into #TempTblEmp
SELECT Items FROM dbo.funSplitListIntoTable(@EmpID,',')
END

create table #TempTblPaymode
(
Paymode nvarchar(max)
)
create table #TempTblWards
(
NewWardNos nvarchar(30)
)

create table #TempPayRes
(
PayRes Nvarchar(max)
)

delete from #TempPayRes
insert into #TempPayRes
select Items from dbo.funSplitListIntoTable(@PaymentResource,',')

delete from #TempTblWards
insert into #TempTblWards
SELECT Items FROM dbo.funSplitListIntoTable(@NewWardNo,',')
delete from #TempTblPaymode
insert into #TempTblPaymode
SELECT Items FROM dbo.funSplitListIntoTable(@PaymentMode,',')
declare @MarathiPaymentMode nvarchar(300)
SELECT   @MarathiPaymentMode = COALESCE(@MarathiPaymentMode + ', ', '') + 
(case when Paymode='Cash' then N'रोख' 
 else (case when Paymode='DD' then N'डी.डी.' 
		else (case when Paymode='Online' then N'ऑनलाईन' 
				else (case when Paymode='Cheque' then N'धनादेश' 
					  else (case when Paymode='Card Payment' then N'कार्ड पेमेंट' 
							else (case when Paymode='RTGS' then N'आरटीजीएस' 
								else (case when Paymode='NEFT' then N'एनईएफटी' 
									else '' 
									end ) 
								end )
							end ) 
					  end ) 
				end ) 
		end ) 
  end ) 
FROM #TempTblPaymode
--SELECT Item FROM dbo.SplitString(@NewWardNo,',')
--select @FinanceYear
create table #TempTbl
(
		OwnerID					int,
		NewWardNo				nvarchar(30),	
		NewPropertyNo			nvarchar(30),
		NewPartitionNo			nvarchar(30),
	    [Owner Name]			nvarchar(max), 
	    [Marathi Owner Name]	nvarchar(max), 
		BillBookNo				nvarchar(30),
		InvoiceNo				nvarchar(max),
		InvoiceNumber			int,
		MerchantTxnRefNumber	nvarchar(max), 
		TransactionDate			nvarchar(30),
		TransactionId			nvarchar(50),
		PaymentMode				nvarchar(max),
		DDChequeNo				nvarchar(max), 
		PaymentResource			nvarchar(max),
		PaymentType				nvarchar(max),
		FinanceYear				int,
		PendingYear				int	,
		PropertyTax				money,
		EmploymentTax			money,
		EducationTax			money,
		SpEducationTax			money,
		DrainCess				money,
		RoadCess				money,
		TreeCess				money,
		SewageDisposalCess		money,
		WaterBenefit			money,
		FireCess				money,
		MajorBuilding			money,
		sanitation				money,
		LightCess				money,
		SpWaterCess				money,
		WaterBill				money,
		Noticefee				money,
		Interest				money,
		Total					money,
		Discount				money,
		ClerkName       nvarchar(max),
		BankName        Varchar(Max),
		BranchName      Varchar(max),
		PayeeName       Varchar(Max),
		ExpiryDate      nvarchar(20),
		Tax4			money,
		Tax5			money,
	    GrpOneInterestDiscount money,
		MiscellaneousFee			money,
		DebitRefID     Varchar(Max),
		Tax1			money,
		Tax2			money,
		Ghanakachara_R		money,
		Ghanakachara_C		money,
		SewageDisposalCessOne				money,
		SewageDisposalCessTwo				money,
		ClearingDate varchar(50),
		PrintedBy Nvarchar(max),
		Tax3			money,
		Amount   money,
		ABCDEF money,
		ChequeBounceFee money,
		    DrainCessDiscount money  
)
--Pending

--select OwnerID from #TempTbl

create table #TempPendingTbl
(
		FinanceYear							int,
		PendingTotalPropertyTax				money,
		PendingTotalEmploymentTax			money,
		PendingTotalEducationTax			money,
		PendingTotalSpEducationTax			money,
		PendingTotalDrainCess				money,
		PendingTotalRoadCess				money,
		PendingTotalTreeCess				money,
		PendingTotalSewageDisposalCess		money,
		PendingTotalWaterBenefit			money,
		PendingTotalFireCess				money,
		PendingTotalMajorBuilding			money,
		PendingTotalsanitation				money,
		PendingTotalLightCess				money,
		PendingTotalSpWaterCess				money,
		PendingTotalWaterBill				money,
		PendingTotalNoticefee				money,
		PendingTotalInterest				money,
		PendingTotalTotal					money,
		PendingTotalDiscount				money,
		PendingTotalTax5			money,
		PendingTotalGrpOneInterestDiscount			money,
		PendingTotalMiscellaneousFee			money,
		PendingTotalTax1			money,
		PendingTotalTax2			money,
		PendingTotalGhanakachara_R			money,
		PendingTotalGhanakachara_C			money,
		PendingTotalSewageDisposalCessOne money,
		PendingTotalSewageDisposalCessTwo money,
		PendingTotalTax3			money,
		PendingTotalTax4			money,
		PendingTotalABCDEF money,
		PendingTotalChequeBounceFee money,
		PendingTotalDrainCessDiscount money


)
--Current
create table #TempCurrntTbl
(
		FinanceYear							int,
		CurrentTotalPropertyTax				money,
		CurrentTotalEmploymentTax			money,
		CurrentTotalEducationTax			money,
		CurrentTotalSpEducationTax			money,
		CurrentTotalDrainCess				money,
		CurrentTotalRoadCess				money,
		CurrentTotalTreeCess				money,
		CurrentTotalSewageDisposalCess		money,
		CurrentTotalWaterBenefit			money,
		CurrentTotalFireCess				money,
		CurrentTotalMajorBuilding			money,
		CurrentTotalsanitation				money,
		CurrentTotalLightCess				money,
		CurrentTotalSpWaterCess				money,
		CurrentTotalWaterBill				money,
		CurrentTotalNoticefee				money,
		CurrentTotalInterest				money,
		CurrentTotalTotal					money,
		CurrentTotalDiscount				money,
		CurrentTotalTax4			money,
		CurrentTotalTax5			money,
		CurrentTotalGrpOneInterestDiscount			money,
		CurrentTotalMiscellaneousFee				money,
		CurrentTotalTax1			money,
		CurrentTotalTax2			money,
		CurrentTotalGhanakachara_R			money,
		CurrentTotalGhanakachara_C			money ,
		CurrentTotalSewageDisposalCessOne	money,
		CurrentTotalSewageDisposalCessTwo	money,
		CurrentTotalTax3			money,
		CurrentTotalABCDEF money,
		CurrentTotalChequeBounceFee MONEY,
		CurrentTotalDrainCessDiscount money 
		
)
--Details
create Table #TempUniquePropertyno
		(
		  OwnerID  int,
		  UniquePropertyNo  varchar(100) 
		)

--PendingForWard
create table #TempPendingTblWard
(       NewWardNo				nvarchar(30),	
		FinanceYear							int,
		PendingTotalPropertyTax				money,
		PendingTotalEmploymentTax			money,
		PendingTotalEducationTax			money,
		PendingTotalSpEducationTax			money,
		PendingTotalDrainCess				money,
		PendingTotalRoadCess				money,
		PendingTotalTreeCess				money,
		PendingTotalSewageDisposalCess		money,
		PendingTotalWaterBenefit			money,
		PendingTotalFireCess				money,
		PendingTotalMajorBuilding			money,
		PendingTotalsanitation				money,
		PendingTotalLightCess				money,
		PendingTotalSpWaterCess				money,
		PendingTotalWaterBill				money,
		PendingTotalNoticefee				money,
		PendingTotalInterest				money,
		PendingTotalTotal					money,
		PendingTotalDiscount				money,
		PendingTotalTax5			        money,
		PendingTotalGrpOneInterestDiscount			        money,
		PendingTotalMiscellaneousFee	   money,
		PendingTotalTax1				   money,
		PendingTotalTax2			   money,
		PendingTotalGhanakachara_R			money,
		PendingTotalGhanakachara_C			money,
		PendingTotalSewageDisposalCessOne money,
		PendingTotalSewageDisposalCessTwo money,
		PendingTotalTax3			   money,
		PendingTotalTax4				money,
		PendingTotalABCDEF money,
		PendingTotalChequeBounceFee money,
		PendingTotalDrainCessDiscount money
)
--CurrentForWard
create table #TempCurrntTblWard
(
        NewWardNo				nvarchar(30),	
		FinanceYear							int,
		CurrentTotalPropertyTax				money,
		CurrentTotalEmploymentTax			money,
		CurrentTotalEducationTax			money,
		CurrentTotalSpEducationTax			money,
		CurrentTotalDrainCess				money,
		CurrentTotalRoadCess				money,
		CurrentTotalTreeCess				money,
		CurrentTotalSewageDisposalCess		money,
		CurrentTotalWaterBenefit			money,
		CurrentTotalFireCess				money,
		CurrentTotalMajorBuilding			money,
		CurrentTotalsanitation				money,
		CurrentTotalLightCess				money,
		CurrentTotalSpWaterCess				money,
		CurrentTotalWaterBill				money,
		CurrentTotalNoticefee				money,
		CurrentTotalInterest				money,
		CurrentTotalTotal					money,
		CurrentTotalDiscount				money,
		CurrentTotalTax4			        money,
		CurrentTotalTax5			        money,
		CurrentTotalGrpOneInterestDiscount			        money,
		CurrentTotalMiscellaneousFee	    money,
		CurrentTotalTax1			        money,
		CurrentTotalTax2					money,
		CurrentTotalGhanakachara_R			money,
		CurrentTotalGhanakachara_C			money,
		CurrentTotalSewageDisposalCessOne	money,
		CurrentTotalSewageDisposalCessTwo	money,
		CurrentTotalTax3					money,
		CurrentTotalABCDEF money,
		CurrentTotalChequeBounceFee MONEY,
		CurrentTotalDrainCessDiscount money 
		
)

		declare @frm nvarchar(250)
		declare @paymode nvarchar(90)
		
		
		set @paymode=isnull(@paymode,'')
		
		set @frm=CONVERT(nvarchar(500), @ToTransactionDate, 103)
		
		if @PaymentMode is not null
		--set @paymode=N'कर भरण्याचा प्रकार: '+@PaymentMode
		set @paymode=+@PaymentMode
		
		if @FromTransactionDate is not null
		--set @frm=N'कर भरण्याचा  दिनांक: '+ CONVERT(nvarchar(500), @FromTransactionDate, 103) +'  -  '+CONVERT(nvarchar(500), @ToTransactionDate, 103)
		set @frm=N'कर भरण्याचा  दिनांक: '+ (convert(varchar(10), @FromTransactionDate, 103) + ' ' +ltrim(right(convert(varchar(20), @FromTransactionDate, 22), 11))) +'  -  '+(convert(varchar(10), @ToTransactionDate, 103) + ' ' +ltrim(right(convert(varchar(20), @ToTransactionDate, 22), 11)))


		

	     
        BEGIN     
			print 'This is 1.1'

		if(@PaymentResource ='online')
		BEGIN
		print @PaymentResource
		
		insert into #TempTbl
		select 
		PropertyMast.OwnerID,
		NewWardNo,
		NewPropertyNo,
		isnull(NewPartitionNo,'')NewPartitionNo,
	    (OwnerTiltle + ' ' + OwnerFirstName + ' ' + OwnerMiddleName + ' ' + OwnerLastName) as 'Owner Name', 
	    --(isnull(MarathiOwnerTilte,'') + ' ' + isnull(MarathiOwnerPrathamNav,'') + ' ' + isnull(MarathiOwnerMadhleNav,'') + ' ' + isnull(MarathiOwnerAadnav,'')) as 'Marathi Owner Name', 
		 --BillTransactionDetails.taxpayername as 'Marathi Owner Name',
		 (CASE WHEN BillTransactionDetails.PaymentResource<>'Tab' and BillTransactionDetails.PaymentResource<>'Online' and BillTransactionDetails.PaymentResource not in ('NTIS','NTISPosting','') THEN BillTransactionDetails.TaxPayerName 
		ELSE (isnull(MarathiOwnerTilte,'') + ' ' + isnull(MarathiOwnerPrathamNav,'') + ' ' + isnull(MarathiOwnerMadhleNav,'') + ' ' + isnull(MarathiOwnerAadnav,''))END) as 'Marathi Owner Name',
		isnull(BillBookNo,'') as BillBookNo,
		(case when lower(isnull(BillTransactionDetails.PaymentResource,''))=lower('online') then isnull(right('00000'+cast(BillTransactionDetails.InvoiceNo as varchar(5)), 5),'') else convert(varchar,BillTransactionDetails.InvoiceNo) END )  as InvoiceNo,
		BillTransactionDetails.InvoiceNo,
		MerchantTxnRefNumber , 
		CONVERT(varchar(13),TransactionDate,103) + ' ' + CONVERT(varchar(10),TransactionDate,8) as TransactionDate,
		isnull(TransactionId,'') as  TransactionId,
		isnull(PaymentMode,'') as PaymentMode,
		isnull(DDChequeNo,'') as DDChequeNo, 
		isnull(PaymentResource,'') as PaymentResource,
		isnull(BillTransactionDetails.PaymentType,'') as PaymentType,
		BillTransactionDetails.FinanceYear,
		BillTransactionDetails.PendingYear,
		isnull(PropertyTax,0)  as  PropertyTax,
		isnull(EmploymentTax,0)  as  EmploymentTax,
		isnull(EducationTax,0)  as  EducationTax,
		isnull(SpEducationTax,0)  as  SpEducationTax,
		isnull(DrainCess,0)  as DrainCess,
		isnull(RoadCess,0)  as  RoadCess,
		isnull(TreeCess,0)  as  TreeCess,
		isnull(SewageDisposalCess,0)  as  SewageDisposalCess,
		isnull(WaterBenefit,0)  as  WaterBenefit,
		isnull(FireCess,0)  as  FireCess,
		isnull(MajorBuilding,0)  MajorBuilding,
		ISNULL(sanitation,0) as sanitation,
		ISNULL(LightCess,0) as LightCess,
		ISNULL(SpWaterCess,0) as SpWaterCess,
		ISNULL(WaterBill,0) as WaterBill,
		ISNULL(Noticefee,0) as Noticefee,
		isnull(Interest,0)  as  Interest,
		(isnull(PropertyTax,0) +
		isnull(EmploymentTax,0) +
		isnull(EducationTax,0) +
		isnull(SpEducationTax,0) +
		isnull(DrainCess,0) +
		isnull(RoadCess,0) +
		isnull(TreeCess,0) +
		isnull(SewageDisposalCess,0) +
		isnull(WaterBenefit,0) +
		isnull(FireCess,0) +
		isnull(MajorBuilding,0) +
		isnull(Interest,0)+
		ISNULL(sanitation,0)+
		ISNULL(LightCess,0) +
		ISNULL(SpWaterCess,0)+
		ISNULL(WaterBill,0)--+
		--ISNULL(Noticefee,0) 
		 ) as Total,
 /*Case when FamilyPlanningDiscountAmount != 0 OR FamilyPlanningDiscountAmount is not null /*Or
			RainWaterHarvestingDiscountAmount != 0 Or RainWaterHarvestingDiscountAmount is not null*/
			then ISNULL(FamilyPlanningDiscountAmount,0)/* + ISNULL(RainWaterHarvestingDiscountAmount,0) */+ ISNULL(Discount,0)  
			else ISNULL(Discount,0) end as discount,*/
			ISNULL(Discount,0)  as discount,
		 ISNULL(UM.Name,'Online') as ClerkName ,
		  BillTransactionDetails.BankName  as BankName ,
		 BillTransactionDetails.BranchName as BranchName ,
		BillTransactionDetails.PayeeName  as  PayeeName,
		CONVERT(varchar(20),BillTransactionDetails.ExpiryDate,103)  as ExpiryDate,
		isnull(Tax4,0)  as  Tax4,
		isnull(Tax5,0)  as  Tax5,
		isnull(GrpOneInterestDiscount,0)  as  GrpOneInterestDiscount,
		isnull(MiscellaneousFee,0)  as  MiscellaneousFee,
		ISNULL(DebitRefID,'') as DebitRefID,
		ISNULL(Tax1,0) as Tax1,
		ISNULL(Tax2,0) as Tax2,
		LightCess as Ghanakachara_R,		
		FireCess as Ghanakachara_C
		,0 as SewageDisposalCessOne
		, 0 as SewageDisposalCessTwo,
		Convert(varchar,Isnull(ClearingDate,''),103) as ClearingDate,
		(select Name from USermodule.UserMaster where UserID=ISNULL(@PrintedBy,''))as PrintedBy,
			ISNULL(Tax3,0) as Tax3,
			ISNULL(Amount,0) as Amount,

			ISNULL(ISNULL(Noticefee,0) + ISNULL(Warrentfee,0) +ISNULL(PaperFee,0)+ISNULL(OtherFee,0),0) as ABCDEF,
		ISNULL(ChequeBounceFee,0) as ChequeBounceFee,
		ISNULL(DrainCessDiscount,0)As DrainCessDiscount
		from PropertyMast inner join BillTransactionDetails 
		on  BillTransactionDetails.OwnerID = PropertyMast.OwnerID 
		inner JOIN online.ZoneSectionDetails ZSD
		ON PropertyMast.NewWardNo=ZSD.Ward
		inner JOIN online.ZoneSectionMaster ZSM
		ON ZSD.ZoneSectionNo=ZSM.ZoneSectionNo
		left join UserModule.UserMaster as UM 
		on UM.UserID=BillTransactionDetails.EmpID
		inner join #TempTblWards tempward
		on PropertyMast.NewWardNo=tempward.NewWardNos
		where 
		--isnull(EmpID,'') like '%'+(case when isnull(@EmpID,'')='' then '' else convert(nvarchar,@EmpID) end)+'%' and 
		--isnull(EmpID,0) in(select empid from #TempTblEmp) and 
	--EmpID in (select item from dbo.SplitString( case when PaymentResource like '%Tab%' then @TabEmpID else @EmpID end ,',')) 
	EmpID IN (SELECT item FROM dbo.SplitString(ISNULL(CASE WHEN PaymentResource LIKE '%Tab%' THEN @TabEmpID ELSE @EmpID END,''),','))and	
		--isnull(EmpID,0) in(select empid from #TempTblEmp) 		and 		
		--PaymentMode like '%'+isnull(@PaymentMode,'')+'%' and
		PaymentMode in(select Paymode  from #TempTblPaymode) and  
		NewWardNo in(select item from dbo.SplitString(@NewWardNo,',')) and
		FinanceYear like '%'+CAST(isnull(@FinanceYear,'') as NVARCHAR(MAX))+'%' and  
		--PaymentType like '%'+isnull(@PaymentType,'')+'%'
		--and	PaymentResource in (Select PayRes from #TempPayRes) 
		(case when isnull(PaymentResource,'')in('','NTIS','NTISPosting') then 'NTIS' else PaymentResource end) in(select PayRes from #TempPayRes)
		--and	ZSD.ZoneSectionNo LIKE '%'+isnull(@ZoneSectionNo,'')+'%'
		and ClearingDate >= @FromTransactionDate and 
		ClearingDate <= @ToTransactionDate  
		
		and isnull(ChequeStatus,'') <>'InProcess'
		and BillTransactionDetails.TransactionId is not null 
		and BillTransactionDetails.TransactionId <> ''
		
		order by 
		dbo.AlphaNum(PropertyMast.NewWardNo),
		dbo.AlphaNum(PropertyMast.NewPropertyNo),
		dbo.AlphaNum(PropertyMast.NewPartitionNo),
		BillTransactionDetails .TransactionDate
		
		end

		else 
		begin

		print @PaymentResource

		insert into #TempTbl
		select 
		PropertyMast.OwnerID,
		NewWardNo,
		NewPropertyNo,
		isnull(NewPartitionNo,'')NewPartitionNo,
	    (OwnerTiltle + ' ' + OwnerFirstName + ' ' + OwnerMiddleName + ' ' + OwnerLastName) as 'Owner Name', 
	    --(isnull(MarathiOwnerTilte,'') + ' ' + isnull(MarathiOwnerPrathamNav,'') + ' ' + isnull(MarathiOwnerMadhleNav,'') + ' ' + isnull(MarathiOwnerAadnav,'')) as 'Marathi Owner Name', 
	 --BillTransactionDetails.taxpayername as 'Marathi Owner Name',
	  (CASE WHEN BillTransactionDetails.PaymentResource<>'Tab' and BillTransactionDetails.PaymentResource<>'Online' and BillTransactionDetails.PaymentResource not in ('NTIS','NTISPosting','') THEN case when isnull(BillTransactionDetails.TaxPayerName,'')='' then  (isnull(MarathiOwnerTilte,'') + ' ' + isnull(MarathiOwnerPrathamNav,'') + ' ' + isnull(MarathiOwnerMadhleNav,'') + ' ' + isnull(MarathiOwnerAadnav,'')) else isnull(BillTransactionDetails.TaxPayerName,'') end
		ELSE (isnull(MarathiOwnerTilte,'') + ' ' + isnull(MarathiOwnerPrathamNav,'') + ' ' + isnull(MarathiOwnerMadhleNav,'') + ' ' + isnull(MarathiOwnerAadnav,''))END) as 'Marathi Owner Name',
	
	isnull(BillBookNo,'') as BillBookNo,
		(case when lower(isnull(BillTransactionDetails.PaymentResource,''))=lower('online') then isnull(right('00000'+cast(BillTransactionDetails.InvoiceNo as varchar(5)), 5),'') else convert(varchar,BillTransactionDetails.InvoiceNo) END )  as InvoiceNo,
		BillTransactionDetails.InvoiceNo,
		MerchantTxnRefNumber , 
		CONVERT(varchar(13),TransactionDate,103) + ' ' + CONVERT(varchar(10),TransactionDate,8) as TransactionDate,
		isnull(TransactionId,'') as  TransactionId,
		isnull(PaymentMode,'') as PaymentMode,
		isnull(DDChequeNo,'') as DDChequeNo, 
		isnull(PaymentResource,'') as PaymentResource,
		isnull(BillTransactionDetails.PaymentType,'') as PaymentType,
		BillTransactionDetails.FinanceYear,
		BillTransactionDetails.PendingYear,
		isnull(PropertyTax,0)  as  PropertyTax,
		isnull(EmploymentTax,0)  as  EmploymentTax,
		isnull(EducationTax,0)  as  EducationTax,
		isnull(SpEducationTax,0)  as  SpEducationTax,
		isnull(DrainCess,0)  as DrainCess,
		isnull(RoadCess,0)  as  RoadCess,
		isnull(TreeCess,0)  as  TreeCess,
		isnull(SewageDisposalCess,0)  as  SewageDisposalCess,
		isnull(WaterBenefit,0)  as  WaterBenefit,
		isnull(FireCess,0)  as  FireCess,
		isnull(MajorBuilding,0)  MajorBuilding,
		ISNULL(sanitation,0) as sanitation,
		ISNULL(LightCess,0) as LightCess,
		ISNULL(SpWaterCess,0) as SpWaterCess,
		ISNULL(WaterBill,0) as WaterBill,
		ISNULL(Noticefee,0) as Noticefee,
		isnull(Interest,0)  as  Interest,
		(isnull(PropertyTax,0) +
		isnull(EmploymentTax,0) +
		isnull(EducationTax,0) +
		isnull(SpEducationTax,0) +
		isnull(DrainCess,0) +
		isnull(RoadCess,0) +
		isnull(TreeCess,0) +
		isnull(SewageDisposalCess,0) +
		isnull(WaterBenefit,0) +
		isnull(FireCess,0) +
		isnull(MajorBuilding,0) +
		isnull(Interest,0)+
		ISNULL(sanitation,0)+
		ISNULL(LightCess,0) +
		ISNULL(SpWaterCess,0)+
		ISNULL(WaterBill,0)--+
		--ISNULL(Noticefee,0) 
		 ) as Total,	 
		/*Case when FamilyPlanningDiscountAmount != 0 OR FamilyPlanningDiscountAmount is not null /*Or
			RainWaterHarvestingDiscountAmount != 0 Or RainWaterHarvestingDiscountAmount is not null*/
			then ISNULL(FamilyPlanningDiscountAmount,0)/* + ISNULL(RainWaterHarvestingDiscountAmount,0)*/ + ISNULL(Discount,0)  
			else ISNULL(Discount,0) end as discount,*/
			ISNULL(Discount,0)  as discount,
		 ISNULL(UM.Name,'Online') as ClerkName ,
		  BillTransactionDetails.BankName  as BankName ,
		 BillTransactionDetails.BranchName as BranchName ,
		BillTransactionDetails.PayeeName  as  PayeeName,
		CONVERT(varchar(20),BillTransactionDetails.ExpiryDate,103)  as ExpiryDate,
		isnull(Tax4,0)  as  Tax4,
		isnull(Tax5,0)  as  Tax5,
		isnull(GrpOneInterestDiscount,0)  as  GrpOneInterestDiscount,
		isnull(MiscellaneousFee,0)  as  MiscellaneousFee,
		ISNULL(DebitRefID,'') as DebitRefID,
		ISNULL(Tax1,0) as Tax1,
		ISNULL(Tax2,0) as Tax2,
		LightCess as Ghanakachara_R,		
		FireCess as Ghanakachara_C
		,0 as SewageDisposalCessOne
		, 0 as SewageDisposalCessTwo,
		Convert(varchar, Isnull(ClearingDate,''), 103) as ClearingDate	,
		(select Name from Usermodule.UserMaster where UserID=ISNULL(@PrintedBy,''))as PrintedBy,
		ISNULL(Tax3,0) as Tax3,
		ISNULL(Amount,0) as Amount,
		ISNULL(ISNULL(Noticefee,0) + ISNULL(Warrentfee,0) +ISNULL(PaperFee,0)+ISNULL(OtherFee,0),0) as ABCDEF,
		ISNULL(ChequeBounceFee,0) as ChequeBounceFee,
		ISNULL(DrainCessDiscount,0)As DrainCessDiscount
		from PropertyMast inner join BillTransactionDetails 
		on  BillTransactionDetails.OwnerID = PropertyMast.OwnerID 
		inner JOIN online.ZoneSectionDetails ZSD
		ON PropertyMast.NewWardNo=ZSD.Ward
		inner JOIN Online.ZoneSectionMaster ZSM
		ON ZSD.ZoneSectionNo=ZSM.ZoneSectionNo
		left join UserModule.UserMaster UM
		on UM.UserID=BillTransactionDetails.EmpID
		inner join #TempTblWards tempward
		on PropertyMast.NewWardNo=tempward.NewWardNos
		where 
		EmpID in (select item from dbo.SplitString( case when PaymentResource like '%Tab%' then @TabEmpID else @EmpID end ,',')) and	
		--NewWardNo in(@NewWardNo) and  
		
		--PaymentMode like '%'+isnull(@PaymentMode,'')+'%' and  /*Nischal*/
		
		PaymentMode in(select Paymode  from #TempTblPaymode) and  
		FinanceYear like'%'+(case when isnull(@FinanceYear,'')='' then '' else convert(nvarchar,@FinanceYear) end)+'%' and  
		--PaymentType like '%'+isnull(@PaymentType,'')+'%' and
		--PaymentResource in (Select PayRes from #TempPayRes) AND 
		(case when isnull(PaymentResource,'')in('','NTIS','NTISPosting') then 'NTIS' else PaymentResource end) in(select PayRes from #TempPayRes) AND
		--ZSD.ZoneSectionNo LIKE '%'+isnull(@ZoneSectionNo,'')+'%' and
		
			isnull(ChequeStatus,'') <>'InProcess' 
		and 
		--BillBookNo LIKE '%'+isnull(@BillBookNo,'')+'%' and
		TransactionDate >= @FromTransactionDate and 
		TransactionDate <= @ToTransactionDate 
		and isnull(ChequeStatus,'') <>'InProcess' 
		and (
			(isnull(BillTransactionDetails.PaymentMode, '') <> 'Online' and isnull(BillTransactionDetails.PaymentResource, '') <> 'online')
			or (BillTransactionDetails.TransactionId is not null and BillTransactionDetails.TransactionId <> '')
		)
		
		order by 
		dbo.AlphaNum(PropertyMast.NewWardNo),
		dbo.AlphaNum(PropertyMast.NewPropertyNo),
		dbo.AlphaNum(PropertyMast.NewPartitionNo),
		dbo.BillTransactionDetails .TransactionDate
		END
	
	
		--Total of Pending
		insert into #TempPendingTblWard
		select 
		NewWardNo,
		FinanceYear,
		sum (isnull(PropertyTax,0)) PendingTotalPropertyTax,
		sum (isnull(EmploymentTax,0)) PendingTotalEmploymentTax,
		sum (isnull(EducationTax,0)) PendingTotalEducationTax,
		sum (isnull(SpEducationTax,0)) PendingTotalSpEducationTax,
		sum (isnull(DrainCess,0)) PendingTotalDrainCess,
		sum (isnull(RoadCess,0)) PendingTotalRoadCess,
		sum (isnull(TreeCess,0)) PendingTotalTreeCess,
		sum (isnull(SewageDisposalCess,0)) PendingTotalSewageDisposalCess,
		sum (isnull(WaterBenefit,0)) PendingTotalWaterBenefit,
		sum (isnull(FireCess,0)) PendingTotalFireCess,
		sum (isnull(MajorBuilding,0)) PendingTotalMajorBuilding, 
		sum (isnull(sanitation,0)) PendingTotalsanitation,
		sum (isnull(LightCess,0)) PendingTotalLightCess,
		sum (isnull(SpWaterCess,0)) PendingTotalSpWaterCess,
		sum (isnull(WaterBill,0)) PendingTotalWaterBill,
		sum (isnull(Noticefee,0)) PendingTotalNoticefee,
		sum (isnull(Interest,0)) PendingTotalInterest,
		sum (isnull(Total,0)) PendingTotalTotal ,
		sum (isnull(Discount,0))PendingTotalDisconunt,
		sum (isnull(Tax5,0))PendingTotalTax5,
		sum (isnull(GrpOneInterestDiscount,0))PendingGrpOneInterestDiscount,
		sum (isnull(MiscellaneousFee,0))PendingTotalMiscellaneousFee,
		sum (isnull(Tax1,0))PendingTotalTax1,
		sum (isnull(Tax2,0))PendingTotalTax2,
		sum (isnull(Ghanakachara_R,0))PendingTotalGhanakachara_R,
		sum (isnull(Ghanakachara_C,0))PendingTotalGhanakachara_C ,
		sum (isnull(SewageDisposalCessOne,0))PendingTotalSewageDisposalCessOne,
		sum (isnull(SewageDisposalCessTwo,0))PendingTotalSewageDisposalCessTwo,
		sum (isnull(Tax3,0))PendingTotalTax3,
		sum (isnull(Tax4,0))PendingTotalTax4,
		sum(ISNULL(ABCDEF,0))PendingTotalABCDEF
		,sum(ISNULL(ChequeBounceFee,0))PendingTotalChequeBounceFee
		,sum(ISNULL(DrainCessDiscount,0))PendingTotalDrainCessDiscount
		
		from  #TempTbl
		group by FinanceYear,PendingYear,NewWardNo
		having FinanceYear=@FinanceYear and PendingYear=(@FinanceYear-1)
		--Total of Current
		insert into #TempCurrntTblWard
		select 
		NewWardNo,
		FinanceYear,
		sum (isnull (PropertyTax,0)) CurrentTotalPropertyTax,
		sum (isnull (EmploymentTax,0)) CurrentTotalEmploymentTax,
		sum (isnull (EducationTax,0)) CurrentTotalEducationTax,
		sum (isnull (SpEducationTax,0)) CurrentTotalSpEducationTax,
		sum (isnull (DrainCess,0)) CurrentTotalDrainCess,
		sum (isnull (RoadCess,0)) CurrentTotalRoadCess,
		sum (isnull (TreeCess,0)) CurrentTotalTreeCess,
		sum (isnull (SewageDisposalCess,0)) CurrentTotalSewageDisposalCess,
		sum (isnull (WaterBenefit,0)) CurrentTotalWaterBenefit,
		sum (isnull (FireCess,0)) CurrentTotalFireCess,
		sum (isnull (MajorBuilding,0)) CurrentTotalMajorBuilding, 
		sum (isnull (sanitation,0)) CurrentTotalsanitation,
		sum (isnull (LightCess,0)) CurrentTotalLightCess,
		sum (isnull (SpWaterCess,0)) CurrentTotalSpWaterCess,
		sum (isnull (WaterBill,0)) CurrentTotalWaterBill,
		sum (isnull (Noticefee,0)) CurrentTotalNoticefee,
		sum (isnull (Interest,0)) CurrentTotalInterest,
		sum (isnull (Total,0)) CurrentTotalTotal, 
		sum (isnull (Discount,0))CurrentTotalDisconunt,
		sum (isnull (Tax4,0))CurrentTotalTax4,
		sum (isnull (Tax5,0))CurrentTotalTax5,
		sum (isnull (GrpOneInterestDiscount,0))CurrentTotalGrpOneInterestDiscount,
		sum (isnull (MiscellaneousFee,0))CurrentTotalMiscellaneousFee,
		sum (isnull (Tax1,0))CurrentTotalTax1,
		sum (isnull (Tax2,0))CurrentTotalTax2,
		sum (isnull (Ghanakachara_R,0))CurrentTotalGhanakachara_R,
		sum (isnull (Ghanakachara_C,0))CurrentTotalGhanakachara_C,
		sum (isnull (SewageDisposalCessOne,0))CurrentTotalSewageDisposalCessOne,
		sum (isnull (SewageDisposalCessTwo,0))CurrentTotalSewageDisposalCessTwo,
		sum (isnull (Tax3,0))CurrentTotalTax3
		,sum(ISNULL(ABCDEF,0))CurrentTotalABCDEF
		,sum(ISNULL(ChequeBounceFee,0))CurrentTotalChequeBounceFee

		,sum(ISNULL(DrainCessDiscount,0))CurrentTotalDrainCessDiscount
		
		
		from  #TempTbl
		group by FinanceYear,PendingYear,NewWardNo
		having FinanceYear=@FinanceYear and PendingYear=@FinanceYear
		--Details
		
		IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'UniquePropertyEntryDetails')
			BEGIN
				
				insert into #TempUniquePropertyno
				(OwnerID,UniquePropertyNo)
				select a.ownerID,upn.UniquePropertyNo
				from #TempTbl a
				left join UniquePropertyEntryDetails upn
				on a.NewWardNo=upn.RefWardNo and a.NewPropertyNo=upn.RefPropertyNo and a.NewPartitionNo=isnull(upn.RefPartitionNo,'')
			END

	/***********************************/
	DECLARE @ward_n NVARCHAR(MAX);

	WITH SortedNewWardNo AS (
		SELECT DISTINCT NewWardNo
		FROM #TempTbl
	)
	SELECT @ward_n = STUFF((
			SELECT ', ' + NewWardNo
			FROM SortedNewWardNo  ORDER BY dbo.AlphaNum(NewWardNo)
			FOR XML PATH('')), 1, 2, '');
	/***********************************/
		--select * from #TempTbl
		select 
		MAX(@frm) as FromDate,
		MAX(CONVERT(VARCHAR(500), @ToTransactionDate, 103)) as ToDate,
		--@FromTransactionDate as FromDate,
		-- @ToTransactionDate as ToDate,
		MAX(@paymode) as Paymode,
		MAX(a.NewWardNos)NewWardNos,
		MAX(isnull(b.PendingTotalPropertyTax,0)) PendingTotalPropertyTax,
		MAX(isnull(b.PendingTotalEmploymentTax,0))PendingTotalEmploymentTax,
		MAX(isnull(b.PendingTotalEducationTax,0))PendingTotalEducationTax,
		MAX(isnull(b.PendingTotalSpEducationTax,0))PendingTotalSpEducationTax,
		MAX(isnull(b.PendingTotalDrainCess,0))PendingTotalDrainCess,
		MAX(isnull(b.PendingTotalRoadCess,0))PendingTotalRoadCess,
		MAX(isnull(b.PendingTotalTreeCess,0))PendingTotalTreeCess,
		MAX(isnull(b.PendingTotalSewageDisposalCess,0))PendingTotalSewageDisposalCess,
		MAX(isnull(b.PendingTotalWaterBenefit,0))PendingTotalWaterBenefit,
		MAX(isnull(b.PendingTotalFireCess,0))PendingTotalFireCess,
		MAX(isnull(b.PendingTotalMajorBuilding,0))PendingTotalMajorBuilding, 
		MAX(isnull(b.PendingTotalsanitation,0))PendingTotalsanitation,
		MAX(isnull(b.PendingTotalLightCess,0))PendingTotalLightCess,
		MAX(isnull(b.PendingTotalSpWaterCess,0))PendingTotalSpWaterCess,
		MAX(isnull(b.PendingTotalWaterBill,0))PendingTotalWaterBill,

		MAX(isnull(b.PendingTotalNoticefee,0))PendingTotalNoticefee,
		MAX(isnull(b.PendingTotalInterest,0))PendingTotalInterest,
		MAX(isnull(b.PendingTotalTotal ,0))PendingTotalTotal,
		MAX(isnull(b.PendingTotalDiscount ,0))PendingTotalDiscount,
		MAX(isnull(b.PendingTotalTax5 ,0))PendingTotalTax5,
		MAX(isnull(b.PendingTotalGrpOneInterestDiscount ,0))PendingTotalGrpOneInterestDiscount,
		MAX(isnull(b.PendingTotalMiscellaneousFee ,0))PendingTotalMiscellaneousFee,
		MAX(isnull(b.PendingTotalTax1 ,0))PendingTotalTax1,
		MAX(isnull(b.PendingTotalTax2 ,0))PendingTotalTax2,
		MAX(isnull(b.PendingTotalGhanakachara_R ,0))PendingTotalGhanakachara_R,
		MAX(isnull(b.PendingTotalGhanakachara_C ,0))PendingTotalGhanakachara_C,
		MAX(isnull(b.PendingTotalSewageDisposalCessOne ,0))PendingTotalSewageDisposalCessOne,
		MAX(isnull(b.PendingTotalSewageDisposalCessTwo ,0))PendingTotalSewageDisposalCessTwo,
		MAX(isnull(b.PendingTotalTax3 ,0))PendingTotalTax3,
		MAX(isnull(b.PendingTotalTax4,0))PendingTotalTax4,


		----------------------
		MAX(isnull(c.CurrentTotalPropertyTax,0))CurrentTotalPropertyTax ,
		MAX(isnull(c.CurrentTotalEmploymentTax,0))CurrentTotalEmploymentTax ,
		MAX(isnull(c.CurrentTotalEducationTax,0))CurrentTotalEducationTax,
		MAX(isnull(c.CurrentTotalSpEducationTax,0))CurrentTotalSpEducationTax,
		MAX(isnull(c.CurrentTotalDrainCess,0))CurrentTotalDrainCess,
		MAX(isnull(c.CurrentTotalRoadCess ,0))CurrentTotalRoadCess,
		MAX(isnull(c.CurrentTotalTreeCess ,0))CurrentTotalTreeCess,
		MAX(isnull(c.CurrentTotalSewageDisposalCess ,0))CurrentTotalSewageDisposalCess,
		MAX(isnull(c.CurrentTotalWaterBenefit,0))CurrentTotalWaterBenefit,
		MAX(isnull(c.CurrentTotalFireCess ,0))CurrentTotalFireCess,
		MAX(isnull(c.CurrentTotalMajorBuilding,0))CurrentTotalMajorBuilding,
		MAX(isnull(c.CurrentTotalsanitation,0))CurrentTotalsanitation,
		MAX(isnull(c.CurrentTotalLightCess,0))CurrentTotalLightCess,
		MAX(isnull(c.CurrentTotalSpWaterCess,0))CurrentTotalSpWaterCess,
		MAX(isnull(c.CurrentTotalWaterBill,0))CurrentTotalWaterBill,
		MAX(isnull(c.CurrentTotalNoticefee ,0))CurrentTotalNoticefee,
		MAX(isnull(c.CurrentTotalInterest,0))CurrentTotalInterest,
		MAX(isnull(c.CurrentTotalTotal,0))CurrentTotalTotal,
		MAX(isnull(c.CurrentTotalDiscount,0))CurrentTotalDiscount,
		MAX(isnull(c.CurrentTotalTax4,0))CurrentTotalTax4,
		MAX(isnull(c.CurrentTotalTax5,0))CurrentTotalTax5,
		MAX(isnull(c.CurrentTotalGrpOneInterestDiscount,0))CurrentTotalGrpOneInterestDiscount,
		MAX(isnull(c.CurrentTotalMiscellaneousFee ,0))CurrentTotalMiscellaneousFee,
		MAX(isnull(c.CurrentTotalTax1,0))CurrentTotalTax1,
		MAX(isnull(c.CurrentTotalTax2,0))CurrentTotalTax2,
		MAX(isnull(c.CurrentTotalGhanakachara_R ,0))CurrentTotalGhanakachara_R,
		MAX(isnull(c.CurrentTotalGhanakachara_C ,0))CurrentTotalGhanakachara_C,
		MAX(isnull(c.CurrentTotalSewageDisposalCessOne ,0))CurrentTotalSewageDisposalCessOne,
		MAX(isnull(c.CurrentTotalSewageDisposalCessTwo ,0))CurrentTotalSewageDisposalCessTwo,
		MAX(isnull(c.CurrentTotalTax3,0))CurrentTotalTax3,
  		MAX(@PrintedName)as PrintedBy,

		MAX(isnull(c.CurrentTotalEmploymentTax,0)+isnull(b.PendingTotalEmploymentTax,0)) TotalEmploymentTax ,
		MAX(isnull(c.CurrentTotalEducationTax,0)+isnull(b.PendingTotalEducationTax,0)) TotalEducationTax ,
		MAX(isnull(c.CurrentTotalSpEducationTax,0)+isnull(b.PendingTotalSpEducationTax,0)) TotalSpEducationTax ,
		MAX(isnull(c.CurrentTotalDrainCess,0)+isnull(b.PendingTotalDrainCess,0)) TotalDrainCess ,
		MAX(isnull(c.CurrentTotalRoadCess,0)+isnull(b.PendingTotalRoadCess,0)) TotalRoadCess ,
		MAX(isnull(c.CurrentTotalTreeCess,0)+isnull(b.PendingTotalTreeCess,0)) TotalTreeCess ,
		MAX(isnull(c.CurrentTotalPropertyTax,0)+isnull(b.PendingTotalPropertyTax,0)) TotalPropertyTax ,
		MAX(isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(b.PendingTotalSewageDisposalCess,0)) TotalSewageDisposalCess ,
		MAX(isnull(c.CurrentTotalWaterBenefit,0)+isnull(b.PendingTotalWaterBenefit,0)) TotalWaterBenefit ,
		MAX(isnull(c.CurrentTotalFireCess,0)+isnull(b.PendingTotalFireCess,0)) TotalFireCess ,
		MAX(isnull(c.CurrentTotalMajorBuilding,0)+isnull(b.PendingTotalMajorBuilding,0)) TotalMajorBuilding ,
		MAX(isnull(c.CurrentTotalsanitation,0)+isnull(b.PendingTotalsanitation,0)) Totalsanitation ,
		MAX(isnull(c.CurrentTotalLightCess,0)+isnull(b.PendingTotalLightCess,0)) TotalLightCess ,
		MAX(isnull(c.CurrentTotalSpWaterCess,0)+isnull(b.PendingTotalSpWaterCess,0)) TotalSpWaterCess ,
		MAX(isnull(round(c.CurrentTotalWaterBill,00),0)+isnull(ROUND(b.PendingTotalWaterBill,00),0)) TotalWaterBill ,
		MAX(c.CurrentTotalNoticefee+b.PendingTotalNoticefee) TotalNoticefee ,
		MAX(c.CurrentTotalInterest+b.PendingTotalInterest) TotalInterest ,
		MAX(c.CurrentTotalTotal+b.PendingTotalTotal) TotalTotal ,
		MAX(c.CurrentTotalDiscount+b.PendingTotalDiscount) TotalDiscount ,
		MAX(c.CurrentTotalTax4+b.PendingTotalTax4) TotalTax4 ,
		MAX(c.CurrentTotalTax5+b.PendingTotalTax5) TotalTax5 ,
		MAX(isnull(c.CurrentTotalTax1,0)+isnull(b.PendingTotalTax1,0)) TotalTax1 ,
		MAX(c.CurrentTotalTax2+b.PendingTotalTax2) TotalTax2 ,
		MAX(isnull(c.CurrentTotalMiscellaneousFee,0)+isnull(b.PendingTotalMiscellaneousFee,0)) TotalMiscellaneousFee ,
		MAX(c.CurrentTotalGrpOneInterestDiscount+b.PendingTotalGrpOneInterestDiscount) TotalGrpOneInterestDiscount ,
		MAX(c.CurrentTotalABCDEF+b.PendingTotalABCDEF) TotalABCDEF ,
		MAX(c.CurrentTotalChequeBounceFee+b.PendingTotalChequeBounceFee) TotalChequeBounceFee ,
		MAX(c.CurrentTotalDrainCessDiscount+b.PendingTotalDrainCessDiscount) TotalDrainCessDiscount ,

		MAX(isnull(c.CurrentTotalTotal,0)-(ISNULL(c.CurrentTotalDrainCessDiscount+c.CurrentTotalDiscount,0))) NetCurrentTax ,
		MAX(isnull(b.PendingTotalTotal,0)-(ISNULL(b.PendingTotalDrainCessDiscount+b.PendingTotalDiscount+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0))) NetPendingTax ,

		MAX(isnull(c.CurrentTotalTotal+b.PendingTotalTotal,0)-(ISNULL(c.CurrentTotalDrainCessDiscount+c.CurrentTotalDiscount,0)+ISNULL(b.PendingTotalDrainCessDiscount+b.PendingTotalDiscount+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0))) NetGrandTotal ,

		MAX(isnull(c.CurrentTotalTotal+c.CurrentTotalABCDEF+c.CurrentTotalMiscellaneousFee+c.CurrentTotalTax4,0)-(ISNULL(c.CurrentTotalDrainCessDiscount+c.CurrentTotalDiscount,0))) NetCurrentTaxWidMis ,
		
		MAX(isnull(b.PendingTotalTotal+b.PendingTotalABCDEF+b.PendingTotalMiscellaneousFee+b.PendingTotalTax4,0)-(ISNULL(b.PendingTotalDrainCessDiscount+b.PendingTotalDiscount+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0))) NetPendingTaxWidMis ,

		MAX((isnull(b.PendingTotalTotal+b.PendingTotalABCDEF+b.PendingTotalMiscellaneousFee+b.PendingTotalTax4,0)+isnull(c.CurrentTotalTotal+c.CurrentTotalABCDEF+c.CurrentTotalMiscellaneousFee+c.CurrentTotalTax4,0))-(ISNULL(b.PendingTotalDrainCessDiscount+b.PendingTotalDiscount+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0)+(ISNULL(c.CurrentTotalDrainCessDiscount+c.CurrentTotalDiscount,0)))) NetTaxWidMis ,

		 --max(CASE WHEN isnull(b.PendingTotalWaterBenefit,0)>0 THEN ROUND(isnull(b.PendingTotalWaterBenefit,0)/2,00) ELSE 0 END) As N'थकीत पाणी पुरवठा लाभकर',
			--max (CASE WHEN isnull(c.CurrentTotalWaterBenefit,0)>0 THEN ROUND(isnull(c.CurrentTotalWaterBenefit,0)/2,00) ELSE 0 END) As N'चालू पाणी पुरवठा लाभकर',
			--max( CASE WHEN (ROUND(isnull(c.CurrentTotalWaterBenefit,0),00)+(ROUND(isnull(b.PendingTotalWaterBenefit,0),00)))>0 THEN 
			-- ROUND(ROUND((isnull(c.CurrentTotalWaterBenefit,0)+isnull(b.PendingTotalWaterBenefit,0)),00)/2,00) ELSE 0 END) As N'Total पाणी पुरवठा लाभकर',


				 max(CASE WHEN ROUND(isnull(b.PendingTotalWaterBenefit,0),00)>0 THEN ROUND(isnull(b.PendingTotalWaterBenefit,0)/2,00)  ELSE 0 END) As N'थकीत पाणी पुरवठा लाभकर',
			max (CASE WHEN ROUND(isnull(c.CurrentTotalWaterBenefit,0),00)>0 THEN  ROUND(isnull(c.CurrentTotalWaterBenefit,0)/2,00)  ELSE 0 END) As N'चालू पाणी पुरवठा लाभकर',
			max( CASE WHEN ( ROUND(isnull(c.CurrentTotalWaterBenefit,0),00) +( ROUND(isnull(b.PendingTotalWaterBenefit,0),00) ))>0 THEN 
			 ROUND(ROUND(isnull(c.CurrentTotalWaterBenefit,0)/2,00) +( ROUND(isnull(b.PendingTotalWaterBenefit,0)/2,00)),00) ELSE 0 END) As N'Total पाणी पुरवठा लाभकर',
			  


			  max( CASE WHEN ROUND(isnull(b.PendingTotalSewageDisposalCess,0),00)>0 THEN ROUND(isnull(b.PendingTotalSewageDisposalCess,0)*0.6666666667,00) ELSE 0 END) As N'थकीत साफसफाई कर',

			 max(CASE WHEN ROUND(isnull(c.CurrentTotalSewageDisposalCess,0),00)>0 THEN (isnull(c.CurrentTotalSewageDisposalCess,0)*0.666666667)  ELSE 0 END) As N'चालू साफसफाई कर',

			max( CASE WHEN ( ROUND(isnull(c.CurrentTotalSewageDisposalCess,0),00)+( ROUND(isnull(b.PendingTotalSewageDisposalCess,0),00) ))>0 THEN ROUND(ROUND(isnull(c.CurrentTotalSewageDisposalCess,0)*0.666666667,00)+( ROUND(isnull(b.PendingTotalSewageDisposalCess,0)*0.666666667,00)),00) ELSE 0 END) As N'Total साफसफाई कर',


			--max( CASE WHEN isnull(b.PendingTotalSewageDisposalCess,0)>0 THEN ROUND(isnull(b.PendingTotalSewageDisposalCess,0)*0.6666666667,00) ELSE 0 END) As N'थकीत साफसफाई कर',
			-- max(CASE WHEN isnull(c.CurrentTotalSewageDisposalCess,0)>0 THEN ROUND(isnull(c.CurrentTotalSewageDisposalCess,0)*0.666666667,00) ELSE 0 END) As N'चालू साफसफाई कर',
			--max( CASE WHEN (isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(b.PendingTotalSewageDisposalCess,0))>0 THEN ROUND((isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(b.PendingTotalSewageDisposalCess,0))*0.666666667,00) ELSE 0 END) As N'Total साफसफाई कर',

			
		 MAX(isnull(b.PendingTotalSewageDisposalCess,0)-ROUND(isnull(b.PendingTotalSewageDisposalCess,0)*0.6666666667,00)) As N'थकीत मलप्रवाह सुविधा लाभकर',

			 MAX(isnull(c.CurrentTotalSewageDisposalCess,0)-(isnull(c.CurrentTotalSewageDisposalCess,0)*0.6666666667)) As N'चालू मलप्रवाह सुविधा लाभकर',

			MAX (isnull(b.PendingTotalSewageDisposalCess,0)-ROUND(isnull(b.PendingTotalSewageDisposalCess,0)*0.6666666667,00)+isnull(c.CurrentTotalSewageDisposalCess,0)-ROUND(isnull(c.CurrentTotalSewageDisposalCess,0)*0.6666666667,00)) As N'TOTAL मलप्रवाह सुविधा लाभकर',

			 max (isnull(b.PendingTotalWaterBenefit,0)-ROUND(isnull(b.PendingTotalWaterBenefit,0)/2,00)) As N'थकीत अग्निशमन कर',
			 max(isnull(c.CurrentTotalWaterBenefit,0)-ROUND(isnull(c.CurrentTotalWaterBenefit,0)/2,00)) As N'चालू अग्निशमन कर',
            max(isnull(b.PendingTotalWaterBenefit,0)-ROUND(isnull(b.PendingTotalWaterBenefit,0)/2,00)+ isnull(c.CurrentTotalWaterBenefit,0)-ROUND(isnull(c.CurrentTotalWaterBenefit,0)/2,00)) As N'TOTAL अग्निशमन कर',

			MAX(ROUND(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalWaterBenefit,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalSpEducationTax,0)+isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalWaterBill,0),00)) As N'Pendingएकुण(१ते10)',
						 MAX(isnull(c.CurrentTotalPropertyTax,0)+isnull(c.CurrentTotalWaterBenefit,0)+isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(c.CurrentTotalLightCess,0)+isnull(c.CurrentTotalFireCess,0)+isnull(c.CurrentTotalSpEducationTax,0)+isnull(c.CurrentTotalRoadCess,0)+isnull(c.CurrentTotalWaterBill,0)) As N'Currentएकुण(१ते10)',
				Max((isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalWaterBenefit,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalSpEducationTax,0)+isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalWaterBill,0))+ (isnull(c.CurrentTotalPropertyTax,0)+isnull(c.CurrentTotalWaterBenefit,0)+isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(c.CurrentTotalLightCess,0)+isnull(c.CurrentTotalFireCess,0)+isnull(c.CurrentTotalSpEducationTax,0)+isnull(c.CurrentTotalRoadCess,0)+isnull(c.CurrentTotalWaterBill,0))) As N'Totalएकुण(१ते10)',

			MAX	(isnull(b.PendingTotalDiscount,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax5,0)) as N'थकीत सुट', 
	MAX	(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax5,0)) as N'चालू सुट',
	MAX(ROUND (isnull(b.PendingTotalDiscount,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax5,0)+isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax5,0),00))as N'TOTAL सुट',
		 --MAX(ROUND(ISNULL(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax5,0)+isnull(b.PendingTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax5,0),0),00)) as N'TOTAL सुट',

		 MAX ((isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalWaterBenefit,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalSpEducationTax,0)+isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalWaterBill,0))-((isnull(b.PendingTotalDiscount,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax5,0)))) As N'थकीत सुट वजा जाता रक्कम',
		 	MAX ((isnull(c.CurrentTotalPropertyTax,0)+isnull(c.CurrentTotalWaterBenefit,0)+isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(c.CurrentTotalLightCess,0)+isnull(c.CurrentTotalFireCess,0)+isnull(c.CurrentTotalSpEducationTax,0)+isnull(c.CurrentTotalRoadCess,0)+isnull(c.CurrentTotalWaterBill,0))-((isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax5,0)))) As N'चालू सुट वजा जाता रक्कम',
		MAX (((isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalWaterBenefit,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalSpEducationTax,0)+isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalWaterBill,0))-((isnull(b.PendingTotalDiscount,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax5,0))))+((isnull(c.CurrentTotalPropertyTax,0)+isnull(c.CurrentTotalWaterBenefit,0)+isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(c.CurrentTotalLightCess,0)+isnull(c.CurrentTotalFireCess,0)+isnull(c.CurrentTotalSpEducationTax,0)+isnull(c.CurrentTotalRoadCess,0)+isnull(c.CurrentTotalWaterBill,0))-((isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax5,0))))) As N'Totalसुट वजा जाता रक्कम',

		 MAX(isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)) As N'थकीत शास्ती',
		MAX	(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)) As N'चालू शास्ती',
		MAX	((isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0))+(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0))) As N'Total शास्ती',

	MAX	(isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+(isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0))) As N'थकीत एकूण(११ते१६)',
		MAX	(isnull(c.CurrentTotalSpWaterCess,0)+isnull(c.CurrentTotalTax1,0)+isnull(c.CurrentTotalTreeCess,0)+isnull(c.CurrentTotalEducationTax,0)+isnull(c.CurrentTotalEmploymentTax,0)+(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0))) As N'चालू एकूण(११ते१६)',
		MAX	((isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+(isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalGrpOneInterestDiscount,0)))+(isnull(c.CurrentTotalSpWaterCess,0)+isnull(c.CurrentTotalTax1,0)+isnull(c.CurrentTotalTreeCess,0)+isnull(c.CurrentTotalEducationTax,0)+isnull(c.CurrentTotalEmploymentTax,0)+(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+isnull(c.CurrentTotalGrpOneInterestDiscount,0)))) As N'Total एकूण(११ते१६)',

	MAX	(ISNULL(isnull(c.CurrentTotalTax3,0)+isnull(b.PendingTotalTax3,0),0))as TotalTax3 ,

		MAX  (ISNULL(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+
isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalsanitation,0)+
isnull(b.PendingTotalDrainCess,0)+
isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalLightCess,0)+
isnull(b.PendingTotalWaterBenefit,0)+
isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalSpEducationTax,0)+
isnull(b.PendingTotalWaterBill,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax3,0)+
isnull(b.PendingTotalTax4,0)
+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalInterest,0)+
isnull(b.PendingTotalNoticefee,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0)
-ISNULL(b.PendingTotalDiscount/*+p.DrainCessDiscount*/+
b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0),0)) as N'(थकीत एकूण १ते१६)',

MAX (Round(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalWaterBenefit,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalSpEducationTax,0)+isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalWaterBill,0)+isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalTax2,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0)+isnull(b.PendingTotalTax3,0),00)
-Round(isnull(b.PendingTotalDiscount,0)+isnull(b.PendingTotalTax5,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0),00)) AS N'थकीत एकूण(१ते१६)ABC',

MAX (Round(isnull(C.CurrentTotalPropertyTax,0)+isnull(c.CurrentTotalWaterBenefit,0)+isnull(c.CurrentTotalSewageDisposalCess,0)+isnull(c.CurrentTotalLightCess,0)+isnull(c.CurrentTotalFireCess,0)+isnull(c.CurrentTotalSpEducationTax,0)+isnull(c.CurrentTotalRoadCess,0)+isnull(c.CurrentTotalWaterBill,0)+isnull(c.CurrentTotalSpWaterCess,0)+isnull(c.CurrentTotalTreeCess,0)+isnull(C.CurrentTotalEducationTax,0)+isnull(C.CurrentTotalEmploymentTax,0)+isnull(c.CurrentTotalTax1,0)+isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0)+isnull(c.CurrentTotalTax3,0),00)
-Round(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalTax5,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0),00)) AS N'Currentएकूण(१ते१६)ABC',


     			MAX (ISNULL(((isnull(C.CurrentTotalPropertyTax,0)+
isnull(c.CurrentTotalWaterBenefit,0)+
isnull(c.CurrentTotalSewageDisposalCess,0)+
isnull(c.CurrentTotalLightCess,0)+
isnull(c.CurrentTotalFireCess,0)+
isnull(c.CurrentTotalSpEducationTax,0)+
isnull(c.CurrentTotalRoadCess,0)+
isnull(c.CurrentTotalWaterBill,0))-
(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalTax5,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0)))+
((isnull(c.CurrentTotalSpWaterCess,0)+
isnull(c.CurrentTotalTreeCess,0)+
isnull(C.CurrentTotalEducationTax,0)+
isnull(C.CurrentTotalEmploymentTax,0)+
isnull(c.CurrentTotalTax1,0))+
(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0))),0)) As N'Currentएकूण(१ते१६)',

	MAX(ISNULL(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+
isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalsanitation,0)+
isnull(b.PendingTotalDrainCess,0)+
isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalLightCess,0)+
isnull(b.PendingTotalWaterBenefit,0)+
isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalSpEducationTax,0)+
isnull(b.PendingTotalWaterBill,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax3,0)+
isnull(b.PendingTotalTax4,0)
+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalInterest,0)+
isnull(b.PendingTotalNoticefee,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0)
-ISNULL(b.PendingTotalDiscount/*+p.DrainCessDiscount*/+
b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0),0)+ISNULL(((isnull(C.CurrentTotalPropertyTax,0)+
isnull(c.CurrentTotalWaterBenefit,0)+
isnull(c.CurrentTotalSewageDisposalCess,0)+
isnull(c.CurrentTotalLightCess,0)+
isnull(c.CurrentTotalFireCess,0)+
isnull(c.CurrentTotalSpEducationTax,0)+
isnull(c.CurrentTotalRoadCess,0)+
isnull(c.CurrentTotalWaterBill,0))-
(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalTax5,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0)))+
((isnull(c.CurrentTotalSpWaterCess,0)+
isnull(c.CurrentTotalTreeCess,0)+
isnull(C.CurrentTotalEducationTax,0)+
isnull(C.CurrentTotalEmploymentTax,0)+
isnull(c.CurrentTotalTax1,0)+
isnull(c.CurrentTotalTax3,0))+
(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0))),0)) As N'Totalएकूण(१ते१६)(१ते१६)',

		MAX (ISNULL(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+
			 isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalsanitation,0)+isnull(b.PendingTotalDrainCess,0)+
			 isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalWaterBenefit,0)+
			isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalSpEducationTax,0)+
			 isnull(b.PendingTotalWaterBill,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax3,0)+isnull(b.PendingTotalTax4,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMiscellaneousFee,0)+isnull(b.PendingTotalNoticefee,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0)
			 			 -ISNULL(b.PendingTotalDiscount/*+p.DrainCessDiscount*/+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0),0)) AS N'थकीत एकूण(अ+ब+क+ड)',

					MAX (ISNULL((((isnull(C.CurrentTotalPropertyTax,0)+
isnull(c.CurrentTotalWaterBenefit,0)+
isnull(c.CurrentTotalSewageDisposalCess,0)+
isnull(c.CurrentTotalLightCess,0)+
isnull(c.CurrentTotalFireCess,0)+
isnull(c.CurrentTotalSpEducationTax,0)+
isnull(c.CurrentTotalRoadCess,0)+
isnull(c.CurrentTotalWaterBill,0))-
(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalTax5,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0)))+
((isnull(c.CurrentTotalSpWaterCess,0)+
isnull(c.CurrentTotalTreeCess,0)+
isnull(C.CurrentTotalEducationTax,0)+
isnull(C.CurrentTotalEmploymentTax,0)+
isnull(c.CurrentTotalTax1,0))+
(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0))))+(ISNULL(c.CurrentTotalMiscellaneousFee,0)+isnull(c.CurrentTotalTax3,0)),0)) As N'चालू एकूण(अ+ब+क+ड)',

MAX(ISNULL(isnull(b.PendingTotalPropertyTax,0)+isnull(b.PendingTotalEducationTax,0)+isnull(b.PendingTotalEmploymentTax,0)+
			 isnull(b.PendingTotalTreeCess,0)+isnull(b.PendingTotalSpWaterCess,0)+isnull(b.PendingTotalsanitation,0)+isnull(b.PendingTotalDrainCess,0)+
			 isnull(b.PendingTotalRoadCess,0)+isnull(b.PendingTotalFireCess,0)+isnull(b.PendingTotalLightCess,0)+isnull(b.PendingTotalWaterBenefit,0)+
			isnull(b.PendingTotalMajorBuilding,0)+isnull(b.PendingTotalSewageDisposalCess,0)+isnull(b.PendingTotalSpEducationTax,0)+
			 isnull(b.PendingTotalWaterBill,0)+isnull(b.PendingTotalTax1,0)+isnull(b.PendingTotalTax2,0)+isnull(b.PendingTotalTax3,0)+isnull(b.PendingTotalTax4,0)+isnull(b.PendingTotalTax5,0)+isnull(b.PendingTotalInterest,0)+isnull(b.PendingTotalMiscellaneousFee,0)+isnull(b.PendingTotalNoticefee,0)+ISNULL(b.PendingTotalGrpOneInterestDiscount,0)
			 			 -ISNULL(b.PendingTotalDiscount/*+p.DrainCessDiscount*/+b.PendingTotalGrpOneInterestDiscount+b.PendingTotalTax5,0)
						 +
						 (((isnull(C.CurrentTotalPropertyTax,0)+
isnull(c.CurrentTotalWaterBenefit,0)+
isnull(c.CurrentTotalSewageDisposalCess,0)+
isnull(c.CurrentTotalLightCess,0)+
isnull(c.CurrentTotalFireCess,0)+
isnull(c.CurrentTotalSpEducationTax,0)+
isnull(c.CurrentTotalRoadCess,0)+
isnull(c.CurrentTotalWaterBill,0))-
(isnull(c.CurrentTotalDiscount,0)+isnull(c.CurrentTotalTax5,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0)))+
((isnull(c.CurrentTotalSpWaterCess,0)+
isnull(c.CurrentTotalTreeCess,0)+
isnull(C.CurrentTotalEducationTax,0)+
isnull(C.CurrentTotalEmploymentTax,0)+
isnull(c.CurrentTotalTax1,0))+
(isnull(c.CurrentTotalInterest,0)+isnull(c.CurrentTotalMajorBuilding,0)+isnull(c.CurrentTotalTax2,0)+ISNULL(c.CurrentTotalGrpOneInterestDiscount,0))))+(ISNULL(c.CurrentTotalMiscellaneousFee,0)+isnull(c.CurrentTotalTax3,0)),0))As N'TotalTotalएकूण(अ+ब+क+ड)',


  MAX(ISNULL(CAST(b.FinanceYear AS VARCHAR(10) ), '') +'-'+ ISNULL(CAST(b.FinanceYear+1 AS VARCHAR(10) ) , '')) AS FinYear,
  				@ward_n as WardNumberforHeader

		
		from  
		#TempTblWards a
		left join #TempPendingTblWard b
		on a.NewWardNos=b.NewWardNo 
		left join #TempCurrntTblWard c
		on a.NewWardNos=c.NewWardNo 
		group by a.NewWardNos 
		order by dbo.AlphaNum(a.NewWardNos)



	--select * from #TempPendingTblWard
	---select * from #TempCurrntTblWard



--Total of both
		select
		sum(isnull(PropertyTax,0)) TotalPropertyTax,
		sum(isnull(EmploymentTax,0)) TotalEmploymentTax,
		sum(isnull(EducationTax,0)) TotalEducationTax,
		sum(isnull(SpEducationTax,0)) TotalSpEducationTax,
		sum(isnull(DrainCess,0)) TotalDrainCess,
		sum(isnull(RoadCess,0)) TotalRoadCess,
		sum(isnull(TreeCess,0)) TotalTreeCess,
		sum(isnull(SewageDisposalCess,0)) TotalSewageDisposalCess,
		sum(isnull(WaterBenefit,0)) TotalWaterBenefit,
		sum(isnull(FireCess,0)) TotalFireCess,
		sum(isnull(MajorBuilding,0)) TotalMajorBuilding, 
		sum(isnull(sanitation,0)) Totalsanitation,
		sum(isnull(LightCess,0)) TotalLightCess,
		sum(isnull(SpWaterCess,0)) TotalSpWaterCess,
		sum(isnull(WaterBill,0)) TotalWaterBill,
		sum(isnull(Noticefee,0)) TotalNoticefee,
		sum(isnull(Interest,0)) TotalInterest,
		sum(isnull(Total,0)) TotalTotalTax ,
		sum(isnull(Discount,0)) TotalDiscount ,
		sum(isnull(Tax4,0)) TotalTax4 ,
		sum(isnull(Tax5,0)) TotalTax5 ,
		sum(isnull(GrpOneInterestDiscount,0)) TotalGrpOneInterestDiscount ,
		sum(isnull(MiscellaneousFee,0))MiscellaneousFee,
		sum(isnull(Tax1,0)) TotalTax1,
		sum(isnull(Tax2,0)) TotalTax2,
		sum(isnull(Ghanakachara_R,0))TotalGhanakachara_R,
		sum(isnull(Ghanakachara_C,0))TotalGhanakachara_C,
		sum(isnull(SewageDisposalCessOne,0))TotalSewageDisposalCessOne,
		sum(isnull(SewageDisposalCessTwo,0))TotalSewageDisposalCessTwo,
		sum(isnull(Tax3,0)) TotalTax3
		
		from  #TempTbl
 		
	drop table #TempTbl
	drop table #TempPendingTbl
	drop table #TempCurrntTbl
END
END
