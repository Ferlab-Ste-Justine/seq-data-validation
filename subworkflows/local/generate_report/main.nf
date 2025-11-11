/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO GENERATE FILE INTEGRITY REPORT
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow FILE_INTEGRITY_REPORT {

    take:
    file_integrity_reports

    main:

    file_integrity_reports.toList()
        .map { it -> buildReport(it) }
        .set { json_reports }

    json_reports.collectFile(
            storeDir: "${params.outdir}/json_report",
            name:  'file_integrity_report.json',
            newLine: true
        )
        .set { final_json_report }

    emit:
    json_report = final_json_report

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Parse output files to extract errors and build report
//
def parseOutput(file, process) {
    def output_message = file.readLines()
    if (process == 'fq_lint') {
        return output_message.findAll{ it -> (it.contains('Error') || it.matches('\\[\\w{4}\\]')) }
        } else if (process == 'seqfu_check') {
            def lines = output_message.findAll{ it -> it.contains('ERR') }
            // get col 8 of each line to get the list of errors
            return lines.collect { it -> it.split('\t')[7] }
        } else if (process == 'picard_validatesamfile') {
            def lines = output_message.findAll{ it -> it.contains('ERROR') }
            return lines.collect { it -> it.split('\t')[0].replace("ERROR:", "") }
        } else if (process == 'gatk4_validatevariants') {
            def lines = output_message.findAll{ it -> it.contains('ERROR') }
            // remove part first part of lines "A USER ERROR has occurred: "
            return lines.collect { it -> it.replace("A USER ERROR has occurred: ", "") }
        } else { // samtools_quickcheck
            return output_message
        }
}

//
// Build JSON report from outputs
//
def buildReport(outputs) {
    def report = [:]

    outputs.each { meta, input1, input2, checks ->
        def status_map = [:]
        def overall_status = 'PASS'
        def error_list = ""
        checks.each { check ->
            def process_name = check.process
            def output_file  = check.output
            def errors = parseOutput(output_file, process_name)
            def check_status = (errors.size() == 0) ? 'PASS' : 'FAIL'
            status_map[process_name] = check_status
            error_list += errors.join(", ")
            if (check_status == 'FAIL') {
                overall_status = 'FAIL'
            }
        }

        report[input1.name] =
            [
            'fileType': meta.fileType,
            'sample_id': meta.sample
            ] +
            (meta.fileType == 'FASTQ' ? ['pair': input2.name ?: null] : ['index': input2.name ?: null]) +
            [
            'experimentalStrategy': meta.sequencingType,
            'status': overall_status,
            'checks': status_map
            ] +
            (error_list.size() > 0 ? ['errors': error_list] : []) +
            [ 'full_path': input1.toString() ]
    }

    def summary_text = "${report.values().count { it -> it.status == 'PASS' }} PASS | ${report.values().count { it -> it.status == 'FAIL' }} FAIL"
    // def summary_text = "${report.count { it -> it.status == 'PASS' }} PASS | ${report.count { it -> it.status == 'FAIL' }} FAIL"

    // Now use JsonBuilder to construct the final JSON
    def builder = new groovy.json.JsonBuilder()
    builder {
        pipeline_version workflow.manifest.version
        date new Date().toString()
        input params.input
        status summary_text
        data report
    }
    return builder.toPrettyString()
}

//
// Dump report to pretty JSON
//
def dumpMapToJSON(reports) {
    def jsonStr = groovy.json.JsonOutput.toJson(reports)
    return groovy.json.JsonOutput.prettyPrint(jsonStr)
}
