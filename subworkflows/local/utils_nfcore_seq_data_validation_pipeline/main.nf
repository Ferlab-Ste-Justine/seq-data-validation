//
// Subworkflow with functionality specific to the Ferlab-Ste-Justine/seq-data-validation pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    replace_id        // boolean: Whether to replace sample IDs based on --id_mapping

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Create channel from input file provided through params.input
    //

    channel
        .fromList(samplesheetToList(params.input, "${projectDir}/assets/schema_input.json"))
        .map { meta, file1, file2 ->
            def fileType = inferFileTypeFromExtension(file1, meta.fileType)
            [ meta + [ participant_sample: "${meta.participant}_${meta.sample}", fileType: fileType ], [file1, file2] ]
        }
        .tap { ch_participant_sample } // save raw input channel
        .map { _meta, files -> files }
        .reduce([:]) { counts, files -> //get line number for each row to construct unique sample ids
            counts[files] = counts.size() + 1
            return counts
        }
        .combine( ch_participant_sample )
        .map { rowno, meta, files ->
            def new_meta = meta + [ file_id: meta.sample+"_"+rowno[files] ]
            [ new_meta, files ]
        }
        .tap { ch_sample_fileid } // save updated input channel with unique sample ids
        .map { meta, _files -> meta }
        .reduce([:]) { counts, meta ->
            if(( replace_id && meta.fileType in ["FASTQ","GVCF","VCF","BAM","CRAM"]) || (!replace_id)) {
                counts[meta.sample] = (counts[meta.sample] ?: 0) + 1
            }
            counts
        }
        .combine(ch_sample_fileid)
        .map { counts, meta, files ->
            def count = counts[meta.sample]
            [ meta + [ count:count ] , files[0], files[1] ] }
        .map { meta, file1, file2 ->
            if (meta.fileType == "FASTQ") {
                if (!file2) {
                    return [ meta + [ single_end:true ], [ file1 ] ]
                } else {
                    return [ meta + [ single_end:false ], [ file1, file2 ] ]
                }
            }
            else {
                if (!file2) {
                    def index_file = findIndex(meta.fileType, file1)
                    return [ meta, [file1, index_file]]
                }
            }
            [ meta, [file1, file2] ]
        }
        .set { ch_samplesheet }

    if (params.id_mapping) {
        channel.fromList(samplesheetToList(params.id_mapping, "${projectDir}/assets/schema_id_mapping.json"))
            .map { row -> [ row[0], row[1] ] }
            .set { id_replace_map }

        ch_samplesheet = ch_samplesheet
            .map { meta, files -> [ meta.sample, [ meta , files ] ] }
            .groupTuple()
            .join(id_replace_map, remainder: true)
            .filter{ _sample, meta_files, _old_id ->
                meta_files!=null
            }
            .view { sample, _meta_files, old_id ->
                if (!old_id) {
                    error("ERROR - No mapping found for sample ID: ${sample} in --id_mapping file. Please check the input samplesheet and id_mapping file.")
                }
                else {
                    log.info("INFO - Replacing sample ID: ${old_id} -> ${sample}")
                }
            }
            .transpose()
            .map{ _sample, meta_files, old_id ->
                def (meta, files) = meta_files
                [meta + [old_id: old_id], files]
            }
    }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    multiqc_report  //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Validate and Infer fileType from file extension
//
def inferFileTypeFromExtension(file, fileType=null) {
    def name = file.getFileName().toString() - '.gz'

    def indexFileTypes = ["BAI","CRAI","CSI","TBI"]
    // GVCF must come before VCF so '.g.vcf' is matched before '.vcf'.
    def fileTypes = ["BED", "JSON", "GFF3", "bigWig", "GVCF","VCF","FASTQ","BAM","BIN","CRAM","BAI","CRAI","CSI","TBI","SAM","CSV","TSV","TXT","MD5","FAM","PED","HTML","XML","IDX"]
    // Override entries for file types whose suffix is not just '.${type.toLowerCase()}'.
    def extraExtensions = [
        "GVCF" : ['.gvcf', '.g.vcf'],
        "FASTQ": ['.fastq', '.fq'],
        "bigWig": ['.bigwig', '.bw'],
        "TSV": ['.tsv', '.tab'],
    ]

    def matchedType = fileTypes.find { type ->
        def extensions = extraExtensions[type] ?: [".${type.toLowerCase()}"]
        extensions.any { extension -> name.endsWith(extension) }
    }

    if (matchedType) {
        // Check if inferred fileType is an index file
        if (matchedType in indexFileTypes || fileType in indexFileTypes) {
            error("Index files can only be provided as file2 accompanied by main data file for file: ${name}. Please check the input samplesheet.")
        }
        // if fileType exists, check it matches inferred fileType - Validation
        // Allow specific case of BW files in samplesheet and rename to bigWig to match dictionary
        if (fileType && matchedType != fileType && fileType != "BW") {
            error("Inferred fileType '${matchedType}' from file extension does not match provided fileType '${fileType}' for file: ${name}. Please check the input samplesheet.")
        }
        return matchedType
    } else {
        if (fileType) {
            log.warn("Could not validate fileType from file extension for file: ${name}. Using provided fileType: ${fileType}.")
            return fileType
        }
        error("Could not infer fileType from file extension for file: ${name}. Please provide fileType in the input samplesheet.")
    }
}

//
// Find index file for alignment or variant files
//
def findIndex(fileType, dataFile) {
    def index = dataFile.toString() + (fileType in ["BAM","CRAM"] ? (fileType == "BAM" ? '.bai' : '.crai') : '.tbi')
    if(!file(index).exists()) {
        log.debug("Index file not found for file: ${dataFile}. Expected index at: ${index}")
        return []
    }
    return file(index)
}

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect{ meta -> meta.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [ metas[0], fastqs ]
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    // TODO nf-core: Optionally add in-text citation tools to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // TODO nf-core: Optionally add bibliographic entries to this list.
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
