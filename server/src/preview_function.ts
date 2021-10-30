// https://www.jameshill.dev/articles/running-gatsby-within-aws-lambda/#super-size-the-lambda

import { Context } from 'aws-lambda';
import { link } from 'linkfs';
import mock from 'mock-require';
import fs from 'fs';
import { tmpdir } from 'os';
import { runtimeRequire } from './runtime_require';
import { publishFiles } from './publish_website';

const tmpDir = tmpdir();

function invokeGatsby(context: Context) {
  const gatsby = runtimeRequire('gatsby/dist/commands/build');

  gatsby({
    directory: __dirname,
    verbose: false,
    browserslist: ['>0.25%', 'not dead'],
    sitePackageJson: runtimeRequire('./package.json'),
  })
    .then(publishFiles)
    .then(context.succeed)
    .catch(context.fail);
}

function rewriteFs() {
  const linkedFs = link(fs, [
    [`${__dirname}/.cache`, `${tmpDir}/.cache`],
    [`${__dirname}/public`, `${tmpDir}/public`],
  ]);

  linkedFs.ReadStream = fs.ReadStream;
  linkedFs.WriteStream = fs.WriteStream;

  mock('fs', linkedFs);
}

export const handler = async (event: any = {}, context: Context): Promise<any> => {
  rewriteFs();
  invokeGatsby(context);
};