"use strict";
import * as tl from "azure-pipelines-task-lib/task";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as fileutils from "azure-pipelines-tasks-docker-common-v2/fileutils";

function getTaskOutputDir(command: string): string {
    let tempDirectory = tl.getVariable('agent.tempDirectory') || os.tmpdir();
    let taskOutputDir = path.join(tempDirectory, "task_outputs");
    return taskOutputDir;
}

export function writeTaskOutput(commandName: string, output: string): string {
    let taskOutputDir = getTaskOutputDir(commandName);
    if (!fs.existsSync(taskOutputDir)) {
        fs.mkdirSync(taskOutputDir);
    }

    let outputFileName = commandName + "_" + Date.now() + ".txt";
    let taskOutputPath = path.join(taskOutputDir, outputFileName);
    if (fileutils.writeFileSync(taskOutputPath, output) == 0) {
        tl.warning(tl.loc('NoDataWrittenOnFile', taskOutputPath));
    }
    
    return taskOutputPath;
}

export function parseStringForDockerIds(output: string, idStringMatch: string = "Successfully built "): string[] {
    let regex = new RegExp(idStringMatch +"[0-9a-f]{12}", "g");
    let idArrayFunction = () => {
        let parsedOutput: string[] = output.match(regex);
        for ( var i = 0; i < parsedOutput.length; i++ ) {
             parsedOutput[i] = parsedOutput[i].replace(idStringMatch, '');
        };
        return parsedOutput;
    };
    let idArray: string[] = idArrayFunction();
    return idArray
}