
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
    serverProcess.kill();
  }
});

test("puppeteer", async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();
  
  // Increase navigation timeout
  await page.goto("http://localhost:8000", { waitUntil: 'networkidle0', timeout: timeout });
  console.log("Page loaded");

  // Verify page title
  const title = await page.title();
  expect(title).toBe("Document");

  // Wait for the main app container to be present
  await page.waitForSelector("#app", { timeout: timeout });
  console.log("#app found");

  // Check for elements within the app container
  const h1 = await page.waitForSelector("#app h1", { timeout: timeout });
  expect(await h1.evaluate(el => el.textContent)).toBe("Snap Demo");
  console.log("h1 found");

  const appDiv = await page.waitForSelector("#app .app", { timeout: timeout });
  expect(appDiv).toBeTruthy(); // Just check for existence
  console.log(".app found");

  const counterH3 = await page.waitForSelector("#app .app h3:nth-of-type(1)", { timeout: timeout });
  expect(await counterH3.evaluate(el => el.textContent)).toBe("Counter");
  console.log("Counter h3 found");

  const decButton = await page.waitForSelector("#app .app button:nth-of-type(1)", { timeout: timeout });
  expect(await decButton.evaluate(el => el.textContent)).toBe("-");
  console.log("Dec button found");

  const incButton = await page.waitForSelector("#app .app button:nth-of-type(2)", { timeout: timeout });
  expect(await incButton.evaluate(el => el.textContent)).toBe("+");
  console.log("Inc button found");

  const countSpan = await page.waitForSelector("#app .app span", { timeout: timeout });
  expect(await countSpan.evaluate(el => el.textContent)).toBe("count 0");
  console.log("Count span found");

  const todosH3 = await page.waitForSelector("#app .app h3:nth-of-type(2)", { timeout: timeout });
  expect(await todosH3.evaluate(el => el.textContent)).toBe("Todos");
  console.log("Todos h3 found");

  const addTodoSection = await page.waitForSelector("#app .app .add-todo-section", { timeout: timeout });
  expect(addTodoSection).toBeTruthy();
  console.log("Add todo section found");

  const newTodoInput = await page.waitForSelector("#app #new-todo", { timeout: timeout });
  expect(await newTodoInput.evaluate(el => el.placeholder)).toBe("Description...");
  expect(await newTodoInput.evaluate(el => el.value)).toBe("");
  console.log("New todo input found");

  const addTodoButton = await page.waitForSelector("#app .add-todo-section button", { timeout: timeout });
  expect(await addTodoButton.evaluate(el => el.textContent)).toBe("Add Todo");
  console.log("Add todo button found");

  const todoList = await page.waitForSelector("#app .app ul", { timeout: timeout });
  expect(todoList).toBeTruthy();
  // Initially, the todo list should be empty
  expect(await todoList.evaluate(el => el.children.length)).toBe(0);
  console.log("Todo list found");

  await browser.close();
}, timeout*3); // Set a higher timeout for the entire test
// import { test, expect } from "bun:test";
// import puppeteer from "puppeteer";

// test("puppeteer", async () => {
//   const browser = await puppeteer.launch({ headless: "new" });
//   const page = await browser.newPage();
//   await page.goto("file:///media/data/Users/Travis/Documents/Code/zig/react-clone/index.html");
//   const title = await page.title();
//   expect(title).toBe("Document");
//   await browser.close();
// });
