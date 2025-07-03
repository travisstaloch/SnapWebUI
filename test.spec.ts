
import { test, expect, beforeAll, afterAll } from "bun:test";
import puppeteer from "puppeteer";
import { spawn } from "child_process";

const timeout = 6000;
let serverProcess;

beforeAll(async () => {
  serverProcess = spawn("bun", ["run", "server.js"], { stdio: "inherit" });
  // Give the server a moment to start up
  await new Promise(resolve => setTimeout(resolve, 1000)); 
});

afterAll(() => {
  if (serverProcess) {
    serverProcess.kill('SIGKILL'); // Use SIGKILL for forceful termination
  }
});

test("puppeteer", async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();

  // page.on('console', msg => {
  //   for (let i = 0; i < msg.args().length; ++i)
  //     console.log(`${i}: ${msg.args()[i]}`);
  // });
  
  // Increase navigation timeout
  await page.goto("http://localhost:8000", { waitUntil: 'networkidle0', timeout: timeout });

  // Wait for the main app container to be present
  await page.waitForSelector("#app", { timeout: timeout });

  // Check for elements within the app container
  const h1 = await page.waitForSelector("#app h1", { timeout: timeout });
  expect(await h1.evaluate(el => el.textContent)).toBe("Snap Demo");

  const appDiv = await page.waitForSelector("#app .app", { timeout: timeout });
  expect(appDiv).toBeTruthy(); // Just check for existence
  expect(await appDiv.evaluate(el => el.className)).toBe("app");

  const counterH3 = await page.waitForSelector("#app .app h3:nth-of-type(1)", { timeout: timeout });
  expect(await counterH3.evaluate(el => el.textContent)).toBe("Counter");

  const decButton = await page.waitForSelector("#app .app button:nth-of-type(1)", { timeout: timeout });
  expect(await decButton.evaluate(el => el.textContent)).toBe("-");
  expect(await decButton.evaluate(el => el.getAttribute('style'))).toBe("margin: 0.25rem");

  const incButton = await page.waitForSelector("#app .app button:nth-of-type(2)", { timeout: timeout });
  expect(await incButton.evaluate(el => el.textContent)).toBe("+");
  expect(await incButton.evaluate(el => el.getAttribute('style'))).toBe("margin: 0.25rem");

  let countSpan = await page.waitForSelector("#app .app span", { timeout: timeout });
  expect(await countSpan.evaluate(el => el.textContent)).toBe("count 0");

  // Test incrementing the counter
  await incButton.click();
  await page.waitForFunction(selector => document.querySelector(selector).textContent === 'count 1', {}, "#app .app span", { timeout: timeout });
  // have to re select since click makes new dom element and countSpan has same, stale content
  countSpan = await page.waitForSelector("#app .app span", { timeout: timeout });
  expect(await countSpan.evaluate(el => el.textContent)).toBe("count 1");

  const todosH3 = await page.waitForSelector("#app .app h3:nth-of-type(2)", { timeout: timeout });
  expect(await todosH3.evaluate(el => el.textContent)).toBe("Todos");

  const addTodoSection = await page.waitForSelector("#app .app .add-todo-section", { timeout: timeout });
  expect(addTodoSection).toBeTruthy();
  expect(await addTodoSection.evaluate(el => el.className)).toBe("add-todo-section");

  const newTodoInput = await page.waitForSelector("#app #new-todo", { timeout: timeout });
  expect(await newTodoInput.evaluate(el => el.placeholder)).toBe("Description...");
  expect(await newTodoInput.evaluate(el => el.value)).toBe("");
  expect(await newTodoInput.evaluate(el => el.getAttribute('type'))).toBe("text");

  const addTodoButton = await page.waitForSelector("#app .add-todo-section button", { timeout: timeout });
  expect(await addTodoButton.evaluate(el => el.textContent)).toBe("Add Todo");
  // Verify that the button is a sibling of the input
  expect(await addTodoButton.evaluate(el => el.previousElementSibling.id)).toBe("new-todo");

  const todoList = await page.waitForSelector("#app .app ul", { timeout: timeout });
  expect(todoList).toBeTruthy();
  expect(await todoList.evaluate(el => el.className)).toBe("todo-list");
  // Initially, the todo list should be empty
  expect(await todoList.evaluate(el => el.children.length)).toBe(0);

  // Test for multiple formats in one attr value
  const dynamicClassDiv = await page.waitForSelector("#multi-dynamic-attr-test", { timeout: timeout });
  expect(await dynamicClassDiv.evaluate(el => el.className)).toBe("foo bar");

  await browser.close();
}, timeout*3); // Set a higher timeout for the entire test

