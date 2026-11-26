// Ejecutar desde PowerShell con npm exec y firebase-tools@15.36.0.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const project = 'aula-presente-movil-juan-2026';
const root = path.resolve(__dirname, '..');
const digest = text => createHash('sha256')
  .update(text.replace(/\r\n/g, '\n')).digest('hex');

async function compare() {
  // npm exec añade el directorio .bin de su paquete temporal al PATH.
  const bin = process.env.PATH.split(path.delimiter).find(directory =>
    path.basename(directory) === '.bin' &&
    fs.existsSync(path.resolve(directory, '../firebase-tools/package.json')));
  if (!bin) throw Error('cli');
  const cli = path.resolve(bin, '../firebase-tools');
  if (require(path.join(cli, 'package.json')).version !== '15.36.0') throw Error('cli');
  const auth = require(path.join(cli, 'lib/auth'));
  const rules = require(path.join(cli, 'lib/gcp/rules'));
  const account = auth.getProjectDefaultAccount(root);
  if (!account) throw Error('auth');
  auth.setActiveAccount({}, account);

  const name = `projects/${project}/releases/cloud.firestore`;
  const release = (await rules.listAllReleases(project)).find(item => item.name === name);
  if (!release) throw Error('release');
  const files = await rules.getRulesetContent(release.rulesetName);
  console.log(release.rulesetName, release.updateTime);
  if (files.length !== 1 || files[0].name !== 'firestore.rules') throw Error('source');
  const local = digest(fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'));
  const active = digest(files[0].content);
  console.log('SHA-256 LF local', local, '\nSHA-256 LF activo', active);
  console.log(active === local ? 'Coinciden' : 'Difieren');
  process.exitCode = active === local ? 0 : 1;
}

compare().catch(error => {
  const messages = {
    cli: 'Ejecuta el comando documentado con firebase-tools@15.36.0.',
    auth: 'Inicia sesión en Firebase CLI para consultar el proyecto.',
    release: 'No se encontró el release de Firestore (default).',
    source: 'La fuente activa no consta de un único firestore.rules.',
  };
  console.error(messages[error.message] || 'Falló la consulta. Comprueba conexión y acceso de lectura.');
  process.exitCode = 2;
});
