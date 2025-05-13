/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_rarevariantburden_pipeline'

include {
  splitJointVCF;
  coverageIntersect;
  normalizeQCAfterSplit;
  normalizeQC;
  annotate;
  skipAnnotation;
  caseGenotypeGDS;
  caseAnnotationGDS;
  skipGenotypeGDS;
  skipAnnotationGDS;
  extractGnomADPositions;
  mergeExtractedPositions;
  RFPrediction;
  CoCoRV;
  mergeCoCoRVResults;
  QQPlotAndFDR;
  postCheck} from '../modules/local/modules.nf'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RAREVARIANTBURDEN {

    take:
    caseJointVCF // caseJointVCF read in from --caseJointVCF
    caseSample // caseSample read in from --caseSample
    
    main:

    // coverage  
    if (params.caseBed == "NA") {
        intersectChannel = Channel.value(params.controlBed)
    } else {
        coverageIntersect(params.caseBed, params.controlBed)
        intersectChannel = coverageIntersect.out
    }

    // create chromosome channel
    chromosomes = params.chrSet.split("\\s+")
    chromChannel = Channel.fromList(Arrays.asList(chromosomes))

    // split joint VCF by chromosome
    // normalize and QC  
    if (params.caseVCFPrefix == "NA") {
        caseJointVCFtbi = params.caseJointVCF + ".tbi"
        splitJointVCF(params.caseJointVCF, caseJointVCFtbi, chromChannel)
        normalizeQCAfterSplit(splitJointVCF.out)
        normalizeQCChannel = normalizeQCAfterSplit.out
    } else {
        normalizeQC(params.caseVCFPrefix, chromChannel, params.caseVCFSuffix)
        normalizeQCChannel = normalizeQC.out
    }

    // annotate
    if (params.caseAnnotatedVCFPrefix == "NA") {
        annotate(normalizeQCChannel, params.build)
        annotateChannel = annotate.out
    } else {
        skipAnnotation(normalizeQCChannel)
        annotateChannel = skipAnnotation.out
    }

    if (params.caseGenotypeGDSPrefix == "NA" && params.caseAnnotationGDSPrefix == "NA") {   
        // case genoypte vcf to gds
        caseGenotypeGDS(normalizeQCChannel)
        caseGenotypeGDSChannel = caseGenotypeGDS.out

        // case annotation to gds
        caseAnnotationGDS(annotateChannel)
        caseAnnotationGDSChannel = caseAnnotationGDS.out
    }
    else {
        //skip annotation and GDS conversion
        skipGenotypeGDS(normalizeQCChannel)
        caseGenotypeGDSChannel = skipGenotypeGDS.out

        skipAnnotationGDS(skipGenotypeGDS.out)
        caseAnnotationGDSChannel = skipAnnotationGDS.out
    }

    // run gnomAD based population prediction
    if (params.casePopulation == "NA") {
        // extract gnomAD positions
        extractGnomADPositions(normalizeQCChannel)

        // merge extracted gnomAD positions
        mergeExtractedPositions(extractGnomADPositions.out.collect())

        RFPrediction(mergeExtractedPositions.out)
        populationChannel = RFPrediction.out[1]
    } else {
        populationChannel = Channel.value(params.casePopulation)
    }

    // run CoCoRV
    // RFPrediction.out.view()
    CoCoRV(caseGenotypeGDSChannel.join(caseAnnotationGDSChannel), 
        intersectChannel,
        populationChannel)

    // merge CoCoRV results
    mergeCoCoRVResults(CoCoRV.out.association_perChr.collect(), CoCoRV.out.caseVariants_perChr.collect(), 
        CoCoRV.out.controlVariants_perChr.collect())

    // QQ plot and FDR
    QQPlotAndFDR(mergeCoCoRVResults.out.association_res, mergeCoCoRVResults.out.caseVariants_res, mergeCoCoRVResults.out.controlVariants_res)

    //postCheck(mergeCoCoRVResults.out[0], params.topK, params.caseControl)
    postCheck(mergeCoCoRVResults.out.association_res, params.topK, params.caseControl, params.build, params.caseSample, 
        normalizeQCChannel.normalizedQCedVCFFile.collect(),
        normalizeQCChannel.normalizedQCedVCFFileIndex.collect(),
        annotateChannel.annotatedFile.collect(),
        annotateChannel.annotatedFileIndex.collect(),
        CoCoRV.out.caseVariants_perChr.collect(), CoCoRV.out.controlVariants_perChr.collect())

    emit:association_res = mergeCoCoRVResults.out.association_res // channel: /path/to/association.tsv
    qqplot       = QQPlotAndFDR.out.qqplot               // channel: /path/to/association.tsv.dominant.nRep1000.pdf

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
