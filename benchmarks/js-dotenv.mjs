import { performance } from "node:perf_hooks";
import dotenv from "dotenv";

const ITERATIONS = 10_000;

function makeBasic(count) {
  const lines = [];

  for (let index = 1; index <= count; index += 1) {
    lines.push(`KEY_${index}=value_${index}`);
  }

  return lines.join("\n");
}

function makeQuoted(count) {
  const lines = [];

  for (let index = 1; index <= count; index += 1) {
    lines.push(`DOUBLE_${index}="value ${index} with spaces and # hash"`);
    lines.push(`SINGLE_${index}='literal ${index} # value'`);
    lines.push(`ESCAPED_${index}="line ${index}\\nnext\\tvalue"`);
  }

  return lines.join("\n");
}

function makeMixed(count) {
  const lines = ["# generated benchmark fixture"];

  for (let index = 1; index <= count; index += 1) {
    lines.push("");
    lines.push(`# block ${index}`);
    lines.push(`export APP_${index}=service_${index}`);
    lines.push(`URL_${index}="https://example.com/${index}?q=value#anchor"`);
    lines.push(`EMPTY_${index}=`);
  }

  return lines.join("\n");
}

const cases = [
  ["basic-128", makeBasic(128)],
  ["quoted-128", makeQuoted(128)],
  ["mixed-128", makeMixed(128)],
];

function countKeys(values) {
  let count = 0;

  for (const _name of Object.keys(values)) {
    count += 1;
  }

  return count;
}

function runCase(name, input) {
  let checksum = 0;

  for (let index = 0; index < 100; index += 1) {
    checksum += countKeys(dotenv.parse(input));
  }

  const startedAt = performance.now();

  for (let index = 0; index < ITERATIONS; index += 1) {
    checksum += countKeys(dotenv.parse(input));
  }

  const elapsedMs = performance.now() - startedAt;
  const opsPerSecond = ITERATIONS / (elapsedMs / 1000);

  console.log(
    `${name.padEnd(12)} ${elapsedMs.toFixed(2).padStart(10)} ms  ${opsPerSecond
      .toFixed(0)
      .padStart(10)} ops/s  checksum=${checksum}`,
  );
}

console.log(`js dotenv parse (${ITERATIONS} iterations)`);

for (const [name, input] of cases) {
  runCase(name, input);
}
