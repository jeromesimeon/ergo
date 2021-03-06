/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

'use strict';

const Fs = require('fs');
const ErgoLoader = require('@accordproject/ergo-compiler').ErgoLoader;
const ErgoCompiler = require('@accordproject/ergo-compiler').Compiler;
const Engine = require('@accordproject/ergo-engine').VMEngine;

/**
 * Load a file or JSON string
 *
 * @param {object} input either a file name or a json string
 * @return {object} JSON object
 */
function getJson(input) {
    let jsonString;
    if (input.file) {
        jsonString = Fs.readFileSync(input.file, 'utf8');
    } else {
        jsonString = input.content;
    }
    return JSON.parse(jsonString);
}

/**
 * Load a template from directory or files
 *
 * @param {string} template - template directory
 * @param {string[]} files - input files
 * @return {Promise<LogicManager>} a Promise to the instantiated logicmanager
 */
async function loadTemplate(template, files) {
    let logicManager;
    if (template) {
        logicManager = await ErgoLoader.fromDirectory(template);
    } else {
        logicManager = await ErgoLoader.fromFiles(files);
    }
    if (logicManager.getScriptManager().getLogic().length === 0) {
        throw new Error('No input ergo found');
    }
    return logicManager;
}

/**
 * Utility class that implements the commands exposed by the Ergo CLI.
 * @class
 */
class Commands {
    /**
     * Send a request an Ergo contract
     *
     * @param {string} template - template directory
     * @param {string[]} files - input files
     * @param {string} contractInput - the contract data
     * @param {string} stateInput - the contract state
     * @param {string} [currentTime] - the definition of 'now', defaults to current time
     * @param {number} [utcOffset] - UTC Offset for this execution, defaults to local offset
     * @param {string[]} requestsInput - the requests
     * @param {boolean} warnings - whether to print warnings
     * @returns {object} Promise to the result of execution
     */
    static async trigger(template,files,contractInput,stateInput,currentTime,utcOffset,requestsInput,warnings) {
        try {
            const logicManager = await loadTemplate(template,files);
            const contractJson = getJson(contractInput);
            let requestsJson = [];
            for (let i = 0; i < requestsInput.length; i++) {
                requestsJson.push(getJson(requestsInput[i]));
            }
            const engine = new Engine();
            let initResponse;
            if (stateInput === null) {
                initResponse = engine.compileAndInit(logicManager, contractJson, {}, currentTime, utcOffset);
            } else {
                const stateJson = getJson(stateInput);
                initResponse = Promise.resolve({ state: stateJson });
            }
            // Get all the other requests and chain execution through Promise.reduce()
            return requestsJson.reduce((promise,requestJson) => {
                return promise.then((result) => {
                    return engine.compileAndTrigger(logicManager, contractJson, requestJson, result.state, currentTime, utcOffset);
                });
            }, initResponse);
        } catch (err) {
            return Promise.reject(err);
        }
    }

    /**
     * Invoke an Ergo contract's clause
     *
     * @param {string} template - template directory
     * @param {string[]} files - input files
     * @param {string} clauseName - the name of the clause to invoke
     * @param {string} contractInput - the contract data
     * @param {string} stateInput - the contract state
     * @param {string} [currentTime] - the definition of 'now', defaults to current time
     * @param {number} [utcOffset] - UTC Offset for this execution, defaults to local offset
     * @param {object} paramsInput - the parameters for the clause
     * @param {boolean} warnings - whether to print warnings
     * @returns {object} Promise to the result of invocation
     */
    static async invoke(template,files,clauseName,contractInput,stateInput,currentTime,utcOffset,paramsInput,warnings) {
        try {
            const logicManager = await loadTemplate(template,files);
            const contractJson = getJson(contractInput);
            const clauseParams = getJson(paramsInput);
            const stateJson = getJson(stateInput);
            const engine = new Engine();
            return engine.compileAndInvoke(logicManager, clauseName, contractJson, clauseParams, stateJson, currentTime, utcOffset);
        } catch (err) {
            return Promise.reject(err);
        }
    }

    /**
     * Invoke init for an Ergo contract
     *
     * @param {string} template - template directory
     * @param {string[]} files - input files
     * @param {string} contractInput - the contract data
     * @param {string} [currentTime] - the definition of 'now', defaults to current time
     * @param {number} [utcOffset] - UTC Offset for this execution, defaults to local offset
     * @param {object} paramsInput - the parameters for the clause
     * @param {boolean} warnings - whether to print warnings
     * @returns {object} Promise to the result of execution
     */
    static async initialize(template,files,contractInput,currentTime,utcOffset,paramsInput,warnings) {
        try {
            const logicManager = await loadTemplate(template,files);
            const contractJson = getJson(contractInput);
            const clauseParams = getJson(paramsInput);
            const engine = new Engine();
            return engine.compileAndInit(logicManager, contractJson, clauseParams, currentTime, utcOffset);
        } catch (err) {
            return Promise.reject(err);
        }
    }

    /**
     * Parse CTO to JSON File
     *
     * @param {string} ctoPath path to CTO model file
     * @returns {string} The name of the generated CTOJ model file
     */
    static parseCTOtoFileSync(ctoPath) {
        const ctoSource = Fs.readFileSync(ctoPath, 'utf8');
        const result = ErgoCompiler.parseCTOtoJSON(ctoSource);
        const outFile = ctoPath.substr(0, ctoPath.lastIndexOf('.')) + '.ctoj';
        Fs.writeFileSync(outFile, JSON.stringify(result));
        return outFile;
    }

    /**
     * Parse CTO to JSON File
     *
     * @param {string} ctoPath path to CTO model file
     * @returns {string} The name of the generated CTOJ model file
     */
    static parseCTOtoFile(ctoPath) {
        return Promise.resolve(this.parseCTOtoFileSync(ctoPath));
    }
}

module.exports = Commands;
