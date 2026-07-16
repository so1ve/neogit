local eq = assert.are.same
local kitty = require("neogit.lib.graph.kitty")

---@param oid string
---@param subject string
---@param parents string? space separated parent oids, defaults to no parents
---@return CommitLogEntry
local function commit(oid, subject, parents)
  return {
    oid = oid,
    subject = subject,
    parent = parents or "",
    author_date = "2024-01-01",
  }
end

---@param result table returned from kitty.build
---@return string[] oid for each row, in order ("" for rows with no associated commit)
local function row_oids(result)
  local oids = {}
  for i, row in ipairs(result) do
    oids[i] = row[1].oid or ""
  end
  return oids
end

---@param result table returned from kitty.build
---@return string[] oid of each row that is a commit row (connector-only rows are dropped), in order
local function commit_row_oids(result)
  local oids = {}
  for _, row in ipairs(result) do
    if row[1].oid then
      oids[#oids + 1] = row[1].oid
    end
  end
  return oids
end

---@param row table a single row from kitty.build's result
---@return string concatenation of every cell's symbol on that row
local function row_symbol(row)
  return row[1].text
end

describe("lib.graph.kitty", function()
  describe("#build", function()
    it("renders one row per commit for a linear history, in the given order", function()
      local result = kitty.build({
        commit("c3", "third", "c2"),
        commit("c2", "second", "c1"),
        commit("c1", "first"),
      }, false)

      eq({ "c3", "c2", "c1" }, row_oids(result))
    end)

    it("uses a distinct symbol for the root commit vs. commits with children", function()
      local result = kitty.build({
        commit("c2", "second", "c1"),
        commit("c1", "first"),
      }, false)

      -- c2 has no children (it's the tip), c1 is the root (no parents)
      -- both are "regular" (non-merge) commits, but the root gets its own end symbol
      assert.is_not.same(row_symbol(result[1]), row_symbol(result[2]))
    end)

    it("uses a distinct symbol for merge commits vs. regular commits", function()
      local result = kitty.build({
        commit("m", "merge", "b a"),
        commit("b", "feature", "a"),
        commit("a", "base"),
      }, false)

      local merge_row, regular_row
      for _, row in ipairs(result) do
        if row[1].oid == "m" then
          merge_row = row
        elseif row[1].oid == "b" then
          regular_row = row
        end
      end

      assert.is_not_nil(merge_row)
      assert.is_not_nil(regular_row)
      assert.is_not.same(row_symbol(merge_row), row_symbol(regular_row))
    end)

    it("handles commits with no common ancestor (different families)", function()
      local result = kitty.build({
        commit("x2", "x-second", "x1"),
        commit("x1", "x-first"),
        commit("y2", "y-second", "y1"),
        commit("y1", "y-first"),
      }, false)

      eq({ "x2", "x1", "y2", "y1" }, row_oids(result))
    end)

    it("resolves the documented bi-crossing scenario without erroring", function()
      -- see the get_is_bi_crossing docstring in kitty.lua for this exact scenario:
      -- j has two parents (g, h), both of which share a common parent i
      local ok, result = pcall(kitty.build, {
        commit("j", "j", "g h"),
        commit("h", "h", "i"),
        commit("g", "g", "i"),
        commit("i", "i"),
      }, false)

      assert.is_true(ok)
      eq({ "j", "h", "g", "i" }, commit_row_oids(result))
    end)

    it("colors every cell 'Purple' when color is disabled", function()
      local result = kitty.build({
        commit("m", "merge", "b a"),
        commit("b", "feature", "a"),
        commit("a", "base"),
      }, false)

      for _, row in ipairs(result) do
        for _, cell in ipairs(row) do
          eq("Purple", cell.color)
        end
      end
    end)

    it("assigns per-branch colors when color is enabled", function()
      local result = kitty.build({
        commit("m", "merge", "b a"),
        commit("b", "feature", "a"),
        commit("a", "base"),
      }, true)

      local saw_non_purple = false
      for _, row in ipairs(result) do
        for _, cell in ipairs(row) do
          if cell.color and cell.color ~= "Purple" and cell.color ~= "BoldPurple" then
            saw_non_purple = true
          end
        end
      end

      assert.is_true(saw_non_purple)
    end)

    it("associates every cell in a commit's rows with that commit's oid", function()
      local result = kitty.build({
        commit("m", "merge", "b a"),
        commit("b", "feature", "a"),
        commit("a", "base"),
      }, false)

      for _, row in ipairs(result) do
        local oid = row[1].oid
        for _, cell in ipairs(row) do
          eq(oid, cell.oid)
        end
      end
    end)
  end)
end)
