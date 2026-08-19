import { describe,expect,it } from "vitest";
import { chunkText } from "./chunking.js";
describe("chunkText",()=>{it("keeps short text intact",()=>expect(chunkText("hello")).toEqual(["hello"]));it("splits long text with overlap",()=>{const result=chunkText("abcdefghij",6,2);expect(result.length).toBeGreaterThan(1);expect(result[0]).toBe("abcdef");expect(result[1].startsWith("ef")).toBe(true);});});
