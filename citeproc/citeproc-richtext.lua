--[[
  Copyright (C) 2021 Zeping Lee
--]]

local richtext = {}

local unicode = require("unicode")

local util = require("citeproc.citeproc-util")


local RichText = {
  contents = nil,
  formats = nil,
  _tag_formats = {
    ["i"] = {["font-style"] = "italic"},
    ["b"] = {["font-weight"] = "bold"},
    ["sup"] = {["vertical-align"] = "sup"},
    ["sub"] = {["vertical-align"] = "sub"},
    ["sc"] = {["font-variant"] = "small-caps"},
    ['span style="font-variant: small-caps;"'] = {["font-variant"] = "smal-caps"},
    ['span class="nocase"'] = {["class"] = "nocase"},
  },
  _default_formats = {
    ["font-style"] = "normal",
    ["font-variant"] = "normal",
    ["font-weight"] = "normal",
    ["text-decoration"] = "none",
    ["vertical-align"] = "baseline",
    ["quotes"] = "false",
  },
  _format_sequence = {
    "font-style",
    "font-variant",
    "font-weight",
    "text-decoration",
    "vertical-align",
    "quotes",
    "display",
  },
  _flip_flop_formats = {
    ["font-style"] = "italic",
    ["font-weight"] = "bold",
    ["quotes"] = "true"
  },
  _type = "RichText",
}

function RichText:shallow_copy()
  local res = richtext.new()
  for _, text in ipairs(self.contents) do
    table.insert(res.contents, text)
  end
  for key, value in ipairs(self.formats) do
    res.formats[key] = value
  end
  return res
end

function RichText:render(formatter, context, punctuation_in_quote)
  self:merge_punctuations()

  if punctuation_in_quote == nil and context then
    punctuation_in_quote = context.style:get_locale_option("punctuation-in-quote")
  end
  if punctuation_in_quote then
    self:move_punctuation_in_quote()
  end

  self:change_case()

  self:clean_formats()

  self:flip_flop()

  return self:_render(formatter, context)
end

function RichText:_render(formatter, context)
  local res = ""
  for _, text in ipairs(self.contents) do
    local str
    if type(text) == "string" then
      if formatter and formatter.text_escape then
        str = formatter.text_escape(text)
      else
        str = text
      end
    else  -- RichText
      str = text:_render(formatter, context)
    end
    -- Remove leading spaces
    if string.sub(res, -1) == " " and string.sub(str, 1, 1) == " " then
      str = string.gsub(str, "^%s+", "")
    end
    res = res .. str
  end
  for _, attr in ipairs(self._format_sequence) do
    local value = self.formats[attr]
    if value then
      local key = string.format("@%s/%s", attr, value)
      if formatter then
        local format = formatter[key]
        if type(format) == "string" then
          res = string.gsub(format, "%%%%STRING%%%%", res)
        elseif type(format) == "function" then
          res = format(res, context)
        end
      end
    end
  end
  return res
end

-- https://github.com/Juris-M/citeproc-js/blob/aa2683f48fe23be459f4ed3be3960e2bb56203f0/src/queue.js#L724
-- Also merge duplicate punctuations.
RichText.punctuation_map = {
  ["!"] = {
    ["."] = "!",
    ["?"] = "!?",
    [":"] = "!",
    [","] = "!,",
    [";"] = "!;",
  },
  ["?"] = {
    ["!"] = "?!",
    ["."] = "?",
    [":"] = "?",
    [","] = "?,",
    [";"] = "?;",
  },
  ["."] = {
    ["!"] = ".!",
    ["?"] = ".?",
    [":"] = ".:",
    [","] = ".,",
    [";"] = ".;",
  },
  [":"] = {
    ["!"] = "!",
    ["?"] = "?",
    ["."] = ":",
    [","] = ":,",
    [";"] = ":;",
  },
  [","] = {
    ["!"] = ",!",
    ["?"] = ",?",
    [":"] = ",:",
    ["."] = ",.",
    [";"] = ",;",
  },
  [";"] = {
    ["!"] = "!",
    ["?"] = "?",
    [":"] = ";",
    [","] = ";,",
    ["."] = ";",
  }
}

RichText.in_quote_punctuations = {
  [","] = true,
  ["."] = true,
  ["?"] = true,
  ["!"] = true,
}

function RichText:merge_punctuations(contents, index)
  for i, text in ipairs(self.contents) do
    if text._type == "RichText" then
      contents, index = text:merge_punctuations(contents, index)
    elseif type(text) == "string" then
      if contents and index then
        local previous_string = contents[index]
        local last_char = string.sub(previous_string, -1)
        local right_punct_map = self.punctuation_map[last_char]
        if right_punct_map then
          local first_char = string.sub(text, 1, 1)
          local new_punctuations = nil
          if first_char == last_char then
            new_punctuations = last_char
          elseif contents == self.contents then
            new_punctuations = right_punct_map[first_char]
          end
          if new_punctuations then
            if #text == 1 then
              table.remove(self.contents, i)
            else
              self.contents[i] = string.sub(text, 2)
            end
            contents[index] = string.sub(previous_string, 1, -2) .. new_punctuations
          end
        end
      end
      contents = self.contents
      index = i
    end
  end
  return contents, index
end

function RichText:move_punctuation_in_quote()
  local i = 1
  while i <= #self.contents do
    local text = self.contents[i]
    if text._type == "RichText" then
      text:move_punctuation_in_quote()
      if text.formats["quotes"] then

        local contents = self.contents
        local last_string = text
        while last_string._type == "RichText" do
          contents = last_string.contents
          last_string = contents[#contents]
        end

        local done = false
        while not done do
          done = true
          last_string = contents[#contents]
          local last_char = string.sub(last_string, -1)
          if i < #self.contents then
            local next_text = self.contents[i + 1]
            if type(next_text) == "string" then
              local first_char = string.sub(next_text, 1, 1)
              if self.in_quote_punctuations[first_char] then
                done = false
                local right_punct_map = self.punctuation_map[last_char]
                if right_punct_map then
                  first_char  = right_punct_map[first_char]
                  last_string = string.sub(last_string, 1, -2)
                end
                contents[#contents] = last_string .. first_char
                if #next_text == 1 then
                  table.remove(self.contents, i + 1)
                else
                  self.contents[i + 1] = string.sub(next_text, 2)
                end
              end
            end
          end
        end
      end
    end
    i = i + 1
  end
end

function RichText:change_case()
  local text_case = self.formats["text-case"]
  if text_case then
    if text_case == "lowercase" then
      self:lowercase()
    elseif text_case == "uppercase" then
      self:uppercase()
    elseif text_case == "capitalize-first" then
      self:capitalize_first()
    elseif text_case == "capitalize-all" then
      self:capitalize_all()
    elseif text_case == "sentence" then
      self:sentence()
    elseif text_case == "title" then
      self:title()
    end
  else
    for _, text in ipairs(self.contents) do
      if type(text) == "table" and text._type == "RichText" then
        text:change_case()
      end
    end
  end
end

function RichText:_change_word_case(state, word_transform, first_tranform)
  if self.formats["vertical-align"] == "sup" or
      self.formats["vertical-align"] == "sub" or
      self.formats["font-variant"] == "small-caps" or
      self.formats["class"] == "nocase" then
    return
  end
  state = state or "after-sentence"
  word_transform = word_transform or function (x) return x end
  first_tranform = first_tranform or word_transform
  for i, text in ipairs(self.contents) do
    if type(text) == "string" then

      local res = ""
      local last_position = 1
      local words = {}
      local word_seps = {
        " ",
        "%-",
        "/",
        util.unicode["no-break space"],
        util.unicode["en dash"],
        util.unicode["em dash"],
      }
      for _, tuple in ipairs(util.split(text, word_seps, nil, true)) do
        local word, punctuation = table.unpack(tuple)
        if state == "after-sentence" then
          res = res .. first_tranform(word)
          if string.match(word, "%w") then
            state = "after-word"
          end
        else
          res = res .. word_transform(word, punctuation)
        end
        res = res .. punctuation
        if string.match(word, "[.!?:]%s*$") then
          state = "after-sentence"
        end
      end

      -- local word_index = 0
      -- local res = string.gsub(text, "%w+", function (word)
      --   word_index = word_index + 1
      --   if word_index == 1 then
      --     return first_tranform(word)
      --   else
      --     return word_transform(word)
      --   end
      -- end)
      -- if string.match(res, "[.!?:]%s*$") then
      --   state = "after-sentence"
      -- end

      self.contents[i] = res
    else
      state = text:_change_word_case(state, word_transform, first_tranform)
    end
  end
  return state
end

function RichText:lowercase()
  local word_transform = unicode.utf8.lower
  self:_change_word_case("after-sentence", word_transform)
end

function RichText:uppercase()
  local word_transform = unicode.utf8.upper
  self:_change_word_case("after-sentence", word_transform)
end

local function capitalize(str)
  local res = string.gsub(str, utf8.charpattern, unicode.utf8.upper, 1)
  return res
end

local function capitalize_if_lower(word)
  if util.is_lower(word) then
    return capitalize(word)
  else
    return word
  end
end

function RichText:capitalize_first(state)
  local first_tranform = capitalize_if_lower
  self:_change_word_case("after-sentence", nil, first_tranform)
end

function RichText:capitalize_all()
  local word_transform = capitalize_if_lower
  self:_change_word_case("after-sentence", word_transform)
end

function RichText:is_upper()
  for _, text in ipairs(self.contents) do
    if type(text) == "string" then
      if not util.is_upper(text) then
        return false
      end
    else
      local res = text:is_upper()
      if not res then
        return false
      end
    end
  end
  return true
end

function RichText:sentence()
  if self:is_upper() then
    local first_tranform = function(word)
      return capitalize(unicode.utf8.lower(word))
    end
    local word_transform = unicode.utf8.lower
    self:_change_word_case("after-sentence", word_transform, first_tranform)
  else
    local first_tranform = capitalize_if_lower
    self:_change_word_case("after-sentence", nil, first_tranform)
  end
end

function RichText:title()
  if self:is_upper() then
    local first_tranform = function(word)
      return capitalize(unicode.utf8.lower(word))
    end
    local word_transform = function(word, sep)
      local res = unicode.utf8.lower(word)
      if not util.stop_words[res] then
        res = capitalize(res)
      end
      return res
    end
    self:_change_word_case("after-sentence", word_transform, first_tranform)
  else
    local first_tranform = capitalize_if_lower
    local word_transform = function(word, sep)
      local lower = unicode.utf8.lower(word)
      -- Stop word before hyphen is treated as a normal word.
      if util.stop_words[lower] and sep ~= "-" then
        return lower
      elseif word == lower then
        return capitalize(word)
      else
        return word
      end
    end
    self:_change_word_case("after-sentence", word_transform, first_tranform)
  end
end

function richtext.concat(str1, str2)
  assert(str1 and str2)
  local res = richtext.new()
  if str1._type ~= "RichText" then
    str1 = richtext.new(str1)
  end
  if next(str1.formats) == nil or str2 == "" then
    -- shallow copy
    res = str1:shallow_copy()
  else
    res = richtext.new()
    res.contents = {str1}
  end
  if str2._type == "RichText" then
    if next(str2.formats) == nil then
      for _, text in ipairs(str2.contents) do
        table.insert(res.contents, text)
      end
    else
      table.insert(res.contents, str2)
    end
  elseif str2 ~= "" then
    table.insert(res.contents, str2)
  end
  return res
end

function richtext.concat_list(list, delimiter)
  -- Strings in the list may be nil thus ipairs() should be avoided.
  -- The delimiter may be nil.
  local res = nil
  for i = 1, #list do
    local text = list[i]
    if text and text ~= "" then
      if res then
        if delimiter and delimiter ~= "" then
          res = richtext.concat(res, delimiter)
        end
        res = richtext.concat(res, text)
      else
        if type(text) == "string" then
          text = richtext.new(text)
        end
        res = text
      end
    end
  end
  return res
end

function RichText:strip_periods()
  local last_string = self
  local contents = self.contents
  while last_string._type == "RichText" do
    contents = last_string.contents
    last_string = contents[#contents]
  end
  if string.sub(last_string, -1) == "." then
    contents[#contents] = string.sub(last_string, 1, -2)
  end
end

function RichText:add_format(attr, value)
  self.formats[attr] = value
end

function RichText:clean_formats(format)
  -- Remove the formats that are default values
  if not format then
    for format, _ in pairs(self._default_formats) do
      self:clean_formats(format)
    end
    return
  end
  if self.formats[format] then
    if self.formats[format] == self._default_formats[format] then
      self.formats[format] = nil
    else
      return
    end
  end
  for _, text in ipairs(self.contents) do
    if type(text) == "table" and text._type == "RichText" then
      text:clean_formats(format)
    end
  end
end

function RichText:flip_flop(attr, value)
  if not attr then
    for attr, _ in pairs(RichText._flip_flop_formats) do
      self:flip_flop(attr)
    end
    return
  end

  if attr == "font-style" then
    if self.formats[attr] == "italic" then
      if value then
        self.formats[attr] = "normal"
        value = nil
      else
        value = "italic"
      end
    end

  elseif attr == "font-weight" then
    if self.formats[attr] == "bold" then
      if value then
        self.formats[attr] = "normal"
        value = nil
      else
        value = "bold"
      end
    end

  elseif attr == "quotes" then
    if self.formats[attr] == "true" then
      if value then
        self.formats[attr] = "inner"
        value = nil
      else
        value = "true"
      end
    end
  end

  for _, text in ipairs(self.contents) do
    if type(text) == "table" and text._type == "RichText" then
      text:flip_flop(attr, value)
    end
  end
end

local RichText_mt = {
  __index = RichText,
  __concat = richtext.concat,
}

local function table_update(t, new_t)
  for key, value in pairs(new_t) do
    t[key] = value
  end
  return t
end

function richtext.new(text, formats)
  local res = {
    contents = {},
    formats = formats or {},
  }

  setmetatable(res, RichText_mt)

  if not text then
    return res
  end

  if type(text) == "string" then

    -- normalize unicode quotes
    text = string.gsub(text, "()'", function(pos)
      if pos == 1 or text[pos - 1] == " " then
        return "‘"
      else
        return "’"
      end
    end)

    local done = false

    while not done do
      local prefix, pos, contents, suffix
      local tag, attributes

      prefix, pos, tag, attributes, contents, suffix = string.match(text, "^(.-)()<(%w+)%s*(.-)>(.-)</%3>(.*)$")
      if contents then
        if tag == "span" then
          formats = RichText._tag_formats[tag .. " " .. attributes]
        else
          formats = RichText._tag_formats[tag]
        end
      end

      -- text = string.gsub(text, '"(.-)"', '“%1”')

      local new_pos = string.match(text, '^.-()“.-”')
      if not pos or (new_pos and new_pos < pos) then
        prefix, contents, suffix = string.match(text, '^(.-)“(.-)”(.*)$')
        if contents then
          pos = new_pos
          formats = {quotes = "true"}
        end
      end

      new_pos = string.match(text, '^.-()".-"')
      if not pos or (new_pos and new_pos < pos) then
        prefix, contents, suffix = string.match(text, '^(.-)"(.-)"(.*)$')
        if contents then
          pos = new_pos
          formats = {quotes = "true"}
        end
      end

      new_pos = string.match(text, "^.-()‘.-’%W")
      if not pos or (new_pos and new_pos < pos) then
        prefix, contents, suffix = string.match(text, "^(.-)‘(.-)’(%W.*)$")
        if contents then
          pos = new_pos
          formats = {quotes = "true"}
        end
      end

      new_pos = string.match(text, "^.-()‘.-’$")
      if not pos or (new_pos and new_pos < pos) then
        prefix, contents, suffix = string.match(text, "^(.-)‘(.-)’$")
        if contents then
          pos = new_pos
          formats = {quotes = "true"}
          suffix = ""
        end
      end

      if contents then
        if prefix ~= "" then
          table.insert(res.contents, prefix)
        end
        table.insert(res.contents, richtext.new(contents, formats))

        if suffix == "" then
          done = true
        else
          text = suffix
        end
      else
        table.insert(res.contents, text)
        done = true
      end

    end

    return res

  elseif type(text) == "table" and text._type == "RichText" then
    return text

  elseif type(text) == "table" then
    return res
  end
  return nil
end


return richtext
