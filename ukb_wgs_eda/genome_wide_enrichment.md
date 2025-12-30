

```bash

# Download counts


seq 1 22 | xargs -I{} -P22 dx download --no-progress -f -r "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr{}/scount"


# Variant groups

mapfile -t var_classes < <(ls scount/*zst | sed -e 's/scount\/chr[0-9]*__//' | sort | uniq)


# Function to sum variants across groups

combine_counts() {
	var="$1"

	zstdcat scount/chr*__${var} |\
	awk '!/#IID/{++samples[$1];hom[$1]+=$2;het[$1]+=$3;sing[$1]+=$4;next}END{for(s in samples) print s,samples[s],sing[s],het[s],hom[s]}' |\
	gzip > "${var%zst}gz"

}

export -f combine_counts

# Run

printf "%s\n" ${var_classes[@]} | xargs -I{} -P15 bash -c 'combine_counts {}'

tar -cvf scounts.tar *.scount.gz

dx upload --path "$DX_PROJECT_CONTEXT_ID:CSQ/" scounts.tar





```




```r
install.packages("R.utils")
require(data.table)



scount_files <- list.files("./csq",pattern = "scount\\.gz$", full.names = FALSE) |>
  gsub(pattern="./csq/",replacement="") |>
  gsub(pattern=".scount.gz",replacement="")

scount_list <- vector(mode="list",length=length(scount_files))



for(i in seq_along(scount_files)){
  
  scount_list[[i]] <- fread(paste0("csq/",scount_files[i],".scount.gz"),header=FALSE,col.names=c('IID','N','SINGLETON','HET','HOM'),sep=' ',na.strings = c('.','NA',''),nThread = 10)

  scount_list[[i]][,c('TYPE','DAMAGING','GROUP','CSQ'):=tstrsplit(scount_files[i],"__",fixed=TRUE)]
}



var_counts <- rbindlist(scount_list)

fwrite(var_counts,"./csq/scounts.csv.gz",sep=",",quote=FALSE,nThread = 10,na = "")


```




```bash
dx download CSQ/scounts.csv.gz


dx download Phenotypes/ukb_phenotypes_copied_from_wh3_files.txt

dx download Phenotypes/Max_Unrel_EUR.txt


```

```r
require(data.table)
require(ggplot2)
require(broom)
require(RNOmni)
require(doMC)
registerDoMC(1)

# covars


ukb_wgs <- fread('covariates/')


wgs_metrics <- fread('covariates/ukb_wgs_metrics.tsv', 
      sep = "\t",
      select = c('id1', 'id2', 'WGS_QCPass','WGS_Coverage', 'WGS_BatchCoverage', 'WGS_Yield', 'WGS_Freemix','WGS_NRD', 'WGS_ReadHaps', 'WGS_Mapped', 'WGS_Provider','WGS_Quantity1', 'WGS_Quantity2', 'WGS_ShipmentPlate', 'WGS_PlateBarcode', 'WGS_PlatePosition'),
      colClasses = list(
        'character' = c('id1','id2','WGS_PlateBarcode', 'WGS_PlatePosition', 'WGS_ShipmentPlate'),
        'factor' = c('WGS_Provider','WGS_QCPass'),
        'numeric' = c('WGS_Yield', 'WGS_BatchCoverage', 'WGS_Coverage', 'WGS_Mapped', 'WGS_Freemix', 'WGS_NRD', 'WGS_Quantity1', 'WGS_Quantity2', 'WGS_ReadHaps')) )





qc_iid <- wgs_metrics[WGS_QCPass == 1,id1]


eur_iid <- fread('csq/ukb_phenotypes_copied_from_wh3_files.txt',select='IID',colClasses=c('IID'='character'))$IID

eur_unrel <- fread('csq/Max_Unrel_EUR.txt',header=FALSE,select='V2')$V2 |> as.character()





eur_phen <- fread('csq/ukb_phenotypes_copied_from_wh3_files.txt',sep=' ')

eur_phen[,id1:=as.character(IID)]

eur_phen <- wgs_metrics[WGS_QCPass == 1, c('id1','WGS_Coverage', 'WGS_BatchCoverage', 'WGS_Yield', 'WGS_Mapped', 'WGS_Provider')] |> merge(x=eur_phen)




var_counts <- fread('csq/scounts.csv.gz',sep=",",header=TRUE,nThread=10)


#var_counts[,ANC:=fcase(IID %in% eur_unrel & IID %in% eur_iid & IID %in% qc_iid, "EUR_MaxUnrel", IID %in% eur_iid & IID %in% qc_iid, "EUR_Relative",  default = "Others")]



per_iid_counts <- var_counts[ ,.(SINGLETON=sum(SINGLETON),URV_HET=sum(HET),URV_HOM=sum(HOM)),by=c("IID","TYPE")] |>
  melt(id.vars=c("IID","TYPE"),value.name="Count",variable.name="GT")


per_iid_counts[, ANC := fcase(IID %in% eur_unrel & IID %in% qc_iid, "EUR_MaxUnrel", IID %in% eur_iid & IID %in% qc_iid, "EUR_Relative",  default = "Others") ]



# var_counts[,.(N=length(unique(IID))),by="ANC"]
#         ANC      N
#      <char>  <int>
# 1: MaxUnrel 380897
# 2:      EUR  71945
# 3:   Others  37699

# total counts

# per_iid_counts <- var_counts[ ,.(ANC=unique(ANC),SINGLETON=sum(SINGLETON),URV_HET=sum(HET),URV_HOM=sum(HOM)),by=c("IID","TYPE")] |>
#   melt(id.vars=c("IID","ANC","TYPE"),value.name="Count",variable.name="GT")




# count median/mad on unrelated samples
per_iid_counts[ANC == "EUR_MaxUnrel" , MED:= median(Count),by=c("TYPE","GT")]
per_iid_counts[ANC == "EUR_MaxUnrel" , MAD:= mad(Count),by=c("TYPE","GT")]


# expand to remaining samples
per_iid_counts[ , MAD:=max(MAD,na.rm=TRUE), by=c("TYPE","GT")]
per_iid_counts[ , MED:=max(MED,na.rm=TRUE), by=c("TYPE","GT")]


# outliers
per_iid_counts[ ANC %in% c("EUR_Relative","EUR_MaxUnrel") & ( Count < (MED - 6*MAD) | Count > (MED + 6*MAD) ) , unique(IID) ] -> iid_outliers


per_iid_counts[ IID %in% iid_outliers, ANC := "EUR_Outliers"]


per_iid_counts[,.(N=length(unique(IID))),by="ANC"]

#             ANC      N
#          <char>  <int>
# 1: EUR_Outliers  26173
# 2: EUR_MaxUnrel 347507
# 3: EUR_Relative  68250
# 4:       Others  48611



# var_counts[ IID %in% iid_outliers, ANC := "EUR_Outliers"]

# var_counts[,.(N=length(unique(IID))),by="ANC"]


# #1: EUR_Outliers  26800
# #2: EUR_MaxUnrel 356100
# #3: EUR_Relative  69942
# #4:       Others  37699

# per_iid_counts[ANC %in% c("Others","EUR_Outliers")]  |>
#   ggplot(aes(x=Count)) +
#   geom_histogram(binwidth = 3) +
#   facet_wrap( TYPE ~ GT, scale="free") +
#   theme_bw() 



# per_iid_counts[ANC %in% c("EUR_Relative","EUR_MaxUnrel")]  |>
#   ggplot(aes(x=Count)) +
#   geom_histogram(binwidth = 3) +
#   facet_wrap( TYPE ~ GT, scale="free") +
#   theme_bw() 




# var_counts[(SINGLETON + HET + HOM) > 0,.N,by=c("TYPE","CSQ")] |> dcast(CSQ ~ TYPE)


## WGS singltons



eur_phen <- per_iid_counts[GT == "SINGLETON", .(count=sum(Count)),by=c("IID","TYPE")] |>
        dcast(IID ~ TYPE,fill=0,value.var="count") |> merge(x=eur_phen,by="IID")



eur_phen[,indel_ratio:=deletion/insertion]




# eur_phen <- per_iid_counts[GT == "SINGLETON", .(count.singletons=sum(Count)),by="IID"] |> merge(x=eur_phen)



# EUR_Outliers


eur_phen_wgs <- eur_phen[IID %in% per_iid_counts[ANC %in% c("EUR_MaxUnrel")] $IID , ]


eur_phen_wgs[,Outlier:="NA"]


eur_phen_med <- eur_phen_wgs[,lapply(.SD,median),.SDcols=paste0('pca',1:25),by="Outlier"] |>
                  melt(id.vars='Outlier',variable.name='PC',value.name='MED')



eur_phen_med <- eur_phen_wgs[,lapply(.SD,mad),.SDcols=paste0('pca',1:25),by="Outlier"] |>
                  melt(id.vars='Outlier',variable.name='PC',value.name='MAD') |> merge(eur_phen_med)


eur_phen_med <- eur_phen_wgs |> melt(id.vars='IID',measure.vars=paste0('pca',1:25),variable.name='PC',value.name='Value') |> merge(eur_phen_med)



eur_phen_med[, Outlier := fifelse( (Value < (MED - 6 * MAD) ) | (Value > (MED + 6 * MAD)), "Yes","No","No")]


pca_outliers <- eur_phen_med[Outlier == "Yes",.N,by="IID"]$IID



eur_phen_wgs[, Outlier := fifelse(IID %in% pca_outliers, "Yes", "No", "NA")]





eur_phen_wgs[!is.na(mean.iq),FIS_method:= "Measured"]
eur_phen_wgs[!is.na(imputed.mean.iq),FIS_method:= "Imputed"]
eur_phen_wgs[,center:=factor(center)]


eur_phen_wgs[Outlier == "No" & !is.na(mean.iq),FIS_average:=RNOmni::RankNorm(mean.iq)]

eur_phen_wgs[Outlier == "No" & !is.na(imputed.mean.iq),FIS_average:=RNOmni::RankNorm(imputed.mean.iq)]

eur_phen_wgs[Outlier == "No" & !is.na(react.time),RT_norm:=RNOmni::RankNorm(react.time)]





eur_phen_wgs[Outlier == "No" & !is.na(SNV),count.snvs:=RNOmni::RankNorm(SNV)]

eur_phen_wgs[Outlier == "No" & !is.na(insertion),count.ins:=RNOmni::RankNorm(insertion)]

eur_phen_wgs[Outlier == "No" & !is.na(deletion),count.del:=RNOmni::RankNorm(deletion)]

eur_phen_wgs[is.na(indel_ratio),indel_ratio:=1]

eur_phen_wgs[Outlier == "No" & !is.na(deletion),count.delins:=RNOmni::RankNorm(indel_ratio)]



per_iid_counts[IID %in% pca_outliers, ANC := "EUR_Outliers"]
var_counts[IID %in% pca_outliers, ANC := "EUR_Outliers"]



per_iid_counts[ANC %in% c("EUR_MaxUnrel")]  |>
  ggplot(aes(x=Count)) +
  geom_histogram(binwidth = 3) +
  facet_wrap( TYPE ~ GT, scale="free") +
  theme_bw() 




# Protein coding

target_samples <- per_iid_counts[ANC %in% c("EUR_MaxUnrel"),IID]

prot_counts <- var_counts[IID %in% target_samples & GROUP == "PROT" ,.(SINGLETON=sum(SINGLETON),URV_HET=sum(HET),URV_HOM=sum(HOM)),by=c("IID","TYPE","CSQ")] |>
                melt(id.vars = c('IID','TYPE','CSQ'), measure.vars = c('URV_HET','URV_HOM','SINGLETON'),variable.name = 'GT', value.name = 'COUNT')


# Collapse TYPE except for indels and intronic variants

#prot_counts[ CSQ == "INFRAME", CSQ:= fcase(TYPE=="deletion","INFRAME_DEL",default="INFRAME_INS")]

#prot_counts[ CSQ == "SPLICE_HC", CSQ:= "PTV_HC"]



prot_counts[ CSQ == "INTRON", CSQ:= fcase(TYPE=="deletion","INTRON_DEL",TYPE=="insertion","INTRON_INS",default="INTRON_SNV")]

prot_counts[GT != "SINGLETON",GT := "URV"]

prot_counts <- prot_counts[CSQ != "UNCLASSIFIED",.(COUNT=sum(COUNT)),by=c("IID","CSQ","GT")]



#prot_counts[,CSQ:=factor(as.character(CSQ),levels=c('PTV_HC','PTV_LC','SPLICE_LC','SPLICE_HC','MIS_HC','MIS_LC','MIS_NC','SYN','INFRAME_DEL','INFRAME_INS','UTR_uORF','UTR_5prime','UTR_3prime','INTRON_SNV','INTRON_INS','INTRON_DEL'))]

prot_counts[,CSQ:=factor(as.character(CSQ),levels=rev(c('PTV_HC','MIS_HC','SPLICE_HC','PTV_LC','MIS_LC','INFRAME','SPLICE_LC','MIS_NC','SYN','UTR_uORF','UTR_5prime','UTR_3prime','INTRON_SNV','INTRON_INS','INTRON_DEL')))]






# several cols named fis



# eur_phen_wgs[!is.na(fis),] |> nrow()
# # 115,204
# eur_phen_wgs[!is.na(fis),fis] |> summary()
# # -8 - 8, float
# eur_phen_wgs[!is.na(fis),fis] |> hist()


# eur_phen_wgs[!is.na(earliest_fis),]|> nrow()
# # 222,533
# eur_phen_wgs[!is.na(earliest_fis),earliest_fis] |> summary()
# # -8 - 8, float
# eur_phen_wgs[!is.na(earliest_fis),earliest_fis] |> hist()


# eur_phen_wgs[!is.na(mean_fis),]|> nrow()
# # 222,533
# eur_phen_wgs[!is.na(mean_fis),mean_fis] |> summary()
# # -8 - 8, float
# eur_phen_wgs[!is.na(mean_fis),mean_fis] |> hist()


# eur_phen_wgs[!is.na(fluid.intel),]|> nrow()
# # 115,204
# eur_phen_wgs[!is.na(fluid.intel),fluid.intel] |> summary()
# # 0-13, integers
# eur_phen_wgs[!is.na(fluid.intel),fluid.intel] |> hist()


# eur_phen_wgs |>
# ggplot() +
# geom_point(aes(x=fis,y=fluid.intel))

# cor.test(eur_phen_wgs$fis,eur_phen_wgs$fluid.intel)





# fis2

# imputed.rawfis
# imputed.rawfis2

# rawfis2



# iq
# imputed.iq



# all.fis2
# all.rawfis2
# all.iq
# all.iq2
# all.earliest.iq
# all.earliest.iq2
# all.mean.iq2
# all.mean.iq

# earliest.iq

# imputed.earliest.iq

# mean.iq


# iq2
# imputed.iq2
# imputed.mean.iq







# eur_phen_wgs[!is.na(mean.iq), ] |> nrow()
# #222,533
# eur_phen_wgs[!is.na(mean.iq),mean.iq] |> summary()
# # -8-8
# eur_phen_wgs[!is.na(mean.iq),mean.iq] |> hist()




# eur_phen_wgs[!is.na(imputed.mean.iq), ] |> nrow()
# #133,566
# eur_phen_wgs[!is.na(imputed.mean.iq),imputed.mean.iq] |> summary()
# # -8-8
# eur_phen_wgs[!is.na(imputed.mean.iq),imputed.mean.iq] |> hist()





# eur_phen_wgs[!is.na(all.mean.iq), ] |> nrow()
# #356,099
# eur_phen_wgs[!is.na(all.mean.iq),all.mean.iq] |> summary()
# eur_phen_wgs[!is.na(all.mean.iq),all.mean.iq] |> sd()
# eur_phen_wgs[!is.na(all.mean.iq),all.mean.iq] |> hist()




# eur_phen_wgs[!is.na(all.mean.iq2), ] |> nrow()
# #356,099
# eur_phen_wgs[!is.na(all.mean.iq2),all.mean.iq2] |> summary()
# eur_phen_wgs[!is.na(all.mean.iq2),all.mean.iq2] |> sd()
# eur_phen_wgs[!is.na(all.mean.iq2),all.mean.iq2] |> hist()

# # IQ2 is normalized and centred?







# eur_phen_wgs[!is.na(FIS_average), ] |> nrow()
# eur_phen_wgs[!is.na(FIS_average),FIS_average] |> summary()
# eur_phen_wgs[!is.na(FIS_average),FIS_average] |> sd()
# eur_phen_wgs[!is.na(FIS_average),FIS_average] |> hist()

# eur_phen_wgs[!is.na(mean.iq), FIS_average] |> summary()
# eur_phen_wgs[!is.na(imputed.mean.iq), FIS_average] |> summary()






# prot_counts[GT == "SINGLETON"] |>
#   ggplot(aes(x=COUNT)) +
#   geom_histogram(binwidth = 1) +
#   facet_wrap("CSQ",scale="free") +
#   theme_bw()



# prot_counts[GT == "URV"] |>
#   ggplot(aes(x=COUNT)) +
#   geom_histogram(binwidth = 1) +
#   facet_wrap("CSQ",scale="free") +
#   theme_bw()









# PTVs


fit_counts <-  merge(eur_phen_wgs,prot_counts)

fit_counts[,sex2:=factor(sex2)]


my_vars <- c( "COUNT","center","birth.year","sex2","age2","age.squared2","agebysex2", "age.squaredbysex2","count.snvs","count.ins","count.ins","count.delins","WGS_Coverage","WGS_BatchCoverage","WGS_Yield","WGS_Mapped","WGS_Provider", paste0("pca",seq(1,25)))
#my_formula <- as.formula(paste("react.time ~ ",paste(my_vars,collapse="+")))
my_formula <- as.formula(paste("FIS_average ~ ",paste(my_vars,collapse="+")))




my_csq <- levels(fit_counts$CSQ)




fit_lm_model <- function(csq,mac,cohort,data) {

my_model <- lm(my_formula,data=data)

my_summary <- tidy(my_model,conf.int = TRUE)

setDT(my_summary)

return(my_summary[term == "COUNT", .(Cohort=cohort,MAC=mac,CSQ=csq, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)])

}




my_estimates <- foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(prot_counts$CSQ)) %:% foreach(cohort = c('Measured','Imputed')) %dopar% { fit_lm_model(csq=csq,cohort=cohort,mac=mac,data=fit_counts[GT == mac & CSQ == csq & FIS_method == cohort ]) } |> unlist(recursive = FALSE) |> unlist(recursive=FALSE) |> rbindlist()








my_estimates[,CSQ:=factor(as.character(CSQ),levels=levels(prot_counts$CSQ))]


my_estimates |> ggplot(aes(y=CSQ,x=Effect,shape=Cohort,color=Cohort)) +
geom_point(position=position_dodge(width=0.8)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.8)) +
theme_bw() +
facet_wrap("MAC") +
geom_vline(xintercept=0)







my_formula <- as.formula(paste("RT_norm ~ ",paste(my_vars,collapse="+")))






fit_lm_model <- function(csq,mac,cohort,data) {

my_model <- lm(my_formula,data=data)

}




my_estimates_rt <- foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(prot_counts$CSQ)) %dopar% { 

my_model <- lm(my_formula,data=fit_counts[GT == mac & CSQ == csq  ])

my_summary <- tidy(my_model,conf.int = TRUE)

setDT(my_summary)

my_summary[term == "COUNT", .(Cohort="RT",MAC=mac,CSQ=csq, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)] } |> unlist(recursive = FALSE) |> rbindlist()








my_estimates_rt[,CSQ:=factor(as.character(CSQ),levels=levels(prot_counts$CSQ))]



rbindlist(list(my_estimates_rt,my_estimates)) |> ggplot(aes(y=CSQ,x=Effect,shape=MAC,color=MAC)) +
geom_point(position=position_dodge(width=0.5)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.5)) +
theme_bw() +
facet_wrap("Cohort") +
geom_vline(xintercept=0)



###



rna_counts <- var_counts[ANC == "EUR_MaxUnrel" & GROUP %in% c("NCRNA","LRNA") , .(SINGLETON=sum(SINGLETON),URV_HET=sum(HET), URV_HOM=sum(HOM)),by=c("IID","CSQ","DAMAGING")] |>
                melt(id.vars = c('IID','DAMAGING','CSQ'), measure.vars = c('URV_HET','URV_HOM','SINGLETON'),variable.name = 'GT', value.name = 'COUNT')

rna_counts[,CSQ:=fcase(CSQ=="SPLICE_HC","Canon_Splice",CSQ %in% c("EXON","SPLICE_LC"),DAMAGING,default="INTRON")]
rna_counts[GT != "SINGLETON",GT := "URV"]


rna_counts <- rna_counts[CSQ != "UNCLASSIFIED",.(COUNT=sum(COUNT)),by=c("IID","CSQ","GT")]


fit_counts <-  merge(eur_phen_wgs,rna_counts)




fit_counts[,CSQ:=factor(as.character(CSQ),levels=rev(c('INTRON','Unlikley','Possible','Plausible','Canon_Splice')))]









my_estimates3 <- foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %:% foreach(cohort = c('Measured','Imputed')) %do% {

  my_formula <- as.formula(paste("FIS_average ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[ GT == mac & CSQ == csq & FIS_method == cohort])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort=cohort,MAC=mac,CSQ=csq, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE) |> unlist(recursive = FALSE) |> rbindlist()






my_estimates4 <- foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %do% {

  my_formula <- as.formula(paste("RT_norm ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[  GT == mac & CSQ == csq  ])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort='RT',MAC=mac,CSQ=csq, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE)   |> rbindlist()







my_estimates <- rbindlist(list(my_estimates3,my_estimates4))


my_estimates[,CSQ:=factor(as.character(CSQ),levels=rev(levels(fit_counts$CSQ)))]




my_estimates |> ggplot(aes(y=CSQ,x=Effect,shape=MAC,color=MAC)) +
geom_point(position=position_dodge(width=0.5)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.5)) +
theme_bw() +
facet_grid(. ~ Cohort ) +
geom_vline(xintercept=0)




###


cre_counts <- var_counts[ANC == "EUR_MaxUnrel" & GROUP =="CRE" , .(SINGLETON=sum(SINGLETON),URV_HET=sum(HET), URV_HOM=sum(HOM)),by=c("IID","CSQ","DAMAGING")] |>
                melt(id.vars = c('IID','DAMAGING','CSQ'), measure.vars = c('URV_HET','URV_HOM','SINGLETON'),variable.name = 'GT', value.name = 'COUNT')

cre_counts[GT != "SINGLETON",GT := "URV"]


cre_counts <- cre_counts[CSQ != "UNCLASSIFIED",.(COUNT=sum(COUNT)),by=c("IID","CSQ","DAMAGING","GT")]


fit_counts <-  merge(eur_phen_wgs,cre_counts)




fit_counts[,CSQ:=factor(as.character(CSQ),levels=rev(c('EMAR_OTHER','EMAR_CTCF','EMAR_TAD','DNST_GENE','UPST_GENE','ENH_InactDist','ENH_ActDist','ENH_InactProx','ENH_ActProx','PROM_Inact','PROM_Act')))]






my_estimates3 <- foreach(pred = c('Unlikley','Possible','Plausible')) %:% foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %:% foreach(cohort = c('Measured','Imputed')) %do% {

  my_formula <- as.formula(paste("FIS_average ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[ DAMAGING == pred & GT == mac & CSQ == csq & FIS_method == cohort])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort=cohort,MAC=mac,CSQ=csq,Tranche=pred, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE) |> unlist(recursive = FALSE) |> unlist(recursive = FALSE) |> rbindlist()






my_estimates4 <- foreach(pred = c('Unlikley','Possible','Plausible')) %:%foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %do% {

  my_formula <- as.formula(paste("RT_norm ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[ DAMAGING == pred &  GT == mac & CSQ == csq  ])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort='RT',MAC=mac,CSQ=csq,Tranche=pred, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE)  |> unlist(recursive = FALSE)  |> rbindlist()





my_estimates <- rbindlist(list(my_estimates3,my_estimates4))


my_estimates[,CSQ:=factor(as.character(CSQ),levels=rev(levels(fit_counts$CSQ)))]




my_estimates[CSQ %in%  c('ENH_InactDist','ENH_ActDist','ENH_InactProx','ENH_ActProx','PROM_Inact','PROM_Act') ] |> ggplot(aes(y=CSQ,x=Effect,shape=MAC,color=MAC)) +
geom_point(position=position_dodge(width=0.5)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.5)) +
theme_bw() +
facet_grid(Tranche ~ Cohort ) +
geom_vline(xintercept=0)







my_estimates[!(CSQ %in%  c('ENH_InactDist','ENH_ActDist','ENH_InactProx','ENH_ActProx','PROM_Inact','PROM_Act') )] |> ggplot(aes(y=CSQ,x=Effect,shape=MAC,color=MAC)) +
geom_point(position=position_dodge(width=0.5)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.5)) +
theme_bw() +
facet_grid(Tranche ~ Cohort ) +
geom_vline(xintercept=0)


# reminaing 





other_counts <- var_counts[IID %in% target_samples & GROUP =="OTHER" , .(SINGLETON=sum(SINGLETON),URV_HET=sum(HET), URV_HOM=sum(HOM)),by=c("IID","CSQ","DAMAGING")] |>
                melt(id.vars = c('IID','DAMAGING','CSQ'), measure.vars = c('URV_HET','URV_HOM','SINGLETON'),variable.name = 'GT', value.name = 'COUNT')



other_counts[GT != "SINGLETON",GT := "URV"]


other_counts <- other_counts[CSQ != "UNCLASSIFIED",.(COUNT=sum(COUNT)),by=c("IID","CSQ","DAMAGING","GT")]


fit_counts <-  merge(eur_phen_wgs,other_counts)




fit_counts[,CSQ:=factor(as.character(CSQ),levels=rev(c('INTERGENIC','DNST_GENE','UPST_GENE','IGTR','FLAG')))]






my_estimates3 <- foreach(pred = c('Unlikley','Possible','Plausible')) %:% foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %:% foreach(cohort = c('Measured','Imputed')) %do% {

  my_formula <- as.formula(paste("FIS_average ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[ DAMAGING == pred & GT == mac & CSQ == csq & FIS_method == cohort])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort=cohort,MAC=mac,CSQ=csq,Tranche=pred, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE) |> unlist(recursive = FALSE) |> unlist(recursive = FALSE) |> rbindlist()






my_estimates4 <- foreach(pred = c('Unlikley','Possible','Plausible')) %:%foreach( mac = c('SINGLETON','URV')) %:% foreach(csq = levels(fit_counts$CSQ) ) %do% {

  my_formula <- as.formula(paste("RT_norm ~ ",paste(my_vars,collapse="+")))

  my_model <- lm(my_formula,data=fit_counts[ DAMAGING == pred &  GT == mac & CSQ == csq  ])

  my_summary <- tidy(my_model,conf.int = TRUE)

  setDT(my_summary)

  my_summary[term == "COUNT", .(Cohort='RT',MAC=mac,CSQ=csq,Tranche=pred, P=p.value, Effect=estimate, CIL=conf.low, CIU=conf.high)]


  } |> unlist(recursive = FALSE)  |> unlist(recursive = FALSE)  |> rbindlist()





my_estimates <- rbindlist(list(my_estimates3,my_estimates4))


my_estimates[,CSQ:=factor(as.character(CSQ),levels=rev(levels(fit_counts$CSQ)))]




my_estimates |> ggplot(aes(y=CSQ,x=Effect,shape=MAC,color=MAC)) +
geom_point(position=position_dodge(width=0.5)) +
geom_errorbar(aes(xmin=CIL,xmax=CIU),width=0,position=position_dodge(width=0.5)) +
theme_bw() +
facet_grid(Tranche ~ Cohort ) +
geom_vline(xintercept=0)







```