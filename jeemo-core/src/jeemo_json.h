#pragma once

#include <cstdlib>
#include <string>

// A deliberately small JSON reader.
//
// The core only ever needs a handful of top-level fields out of a message:
// type, v, menuId, nonce, at, from. It never needs to walk into the items
// array, which the UI handles. So rather than carrying a JSON library into a
// Qt-free module, this scans the top level of an object and hands back one
// value, leaving everything else untouched.
//
// Messages are re-sent byte for byte as they arrived, so nothing here has to
// round-trip or re-serialise, and an unknown field added by a later version
// of a UI survives a hop through an older core.

namespace jeemo {

// Returns the raw token for `key` at the top level of `json`, with quotes
// stripped for strings. Returns "" when the key is absent.
inline std::string field(const std::string& json, const std::string& key)
{
    const size_t n = json.size();
    size_t i = 0;
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    // Walk the text once, tracking nesting so that a "nonce" buried inside a
    // nested object is not mistaken for the top-level one.
    std::string pendingKey;
    bool readingKey = false;
    size_t keyStart = 0;

    while (i < n) {
        const char c = json[i];

        if (inString) {
            if (escaped)            escaped = false;
            else if (c == '\\')     escaped = true;
            else if (c == '"') {
                inString = false;
                if (readingKey) {
                    pendingKey = json.substr(keyStart, i - keyStart);
                    readingKey = false;
                }
            }
            ++i;
            continue;
        }

        if (c == '"') {
            inString = true;
            // Only a string opening at depth 1 can be a key we care about.
            if (depth == 1) { readingKey = true; keyStart = i + 1; }
            ++i;
            continue;
        }

        if (c == '{' || c == '[') { ++depth; ++i; continue; }
        if (c == '}' || c == ']') { --depth; ++i; continue; }

        if (c == ':' && depth == 1 && pendingKey == key) {
            // Found it. Read the value that follows.
            ++i;
            while (i < n && (json[i] == ' ' || json[i] == '\t'
                             || json[i] == '\n' || json[i] == '\r')) ++i;
            if (i >= n) return "";

            if (json[i] == '"') {
                ++i;
                std::string out;
                bool esc = false;
                while (i < n) {
                    const char d = json[i];
                    if (esc) {
                        // Only the escapes our own messages can contain.
                        if      (d == 'n')  out += '\n';
                        else if (d == 't')  out += '\t';
                        else if (d == 'r')  out += '\r';
                        else                out += d;
                        esc = false;
                    } else if (d == '\\') {
                        esc = true;
                    } else if (d == '"') {
                        break;
                    } else {
                        out += d;
                    }
                    ++i;
                }
                return out;
            }

            // A number, true, false or null: read to the next delimiter.
            size_t start = i;
            while (i < n && json[i] != ',' && json[i] != '}' && json[i] != ']')
                ++i;
            std::string out = json.substr(start, i - start);
            while (!out.empty() && (out.back() == ' ' || out.back() == '\n'
                                    || out.back() == '\t' || out.back() == '\r'))
                out.pop_back();
            return out;
        }

        if (c == ',' && depth == 1)
            pendingKey.clear();

        ++i;
    }
    return "";
}

inline long long number(const std::string& json, const std::string& key)
{
    const std::string v = field(json, key);
    if (v.empty()) return 0;
    return std::strtoll(v.c_str(), nullptr, 10);
}

// Adds "key":"value" to a flat object, or replaces it if already present.
// Only used for the two fields the core sets itself, `from` and `at`.
inline std::string withField(const std::string& json,
                             const std::string& key,
                             const std::string& rawValue)
{
    if (!field(json, key).empty())
        return json;                       // caller already supplied it

    const size_t open = json.find('{');
    if (open == std::string::npos)
        return json;

    // An empty object takes no comma.
    size_t probe = open + 1;
    while (probe < json.size()
           && (json[probe] == ' ' || json[probe] == '\n'
               || json[probe] == '\t' || json[probe] == '\r'))
        ++probe;
    const bool empty = (probe < json.size() && json[probe] == '}');

    std::string insert = "\"" + key + "\":" + rawValue;
    if (!empty) insert += ",";
    return json.substr(0, open + 1) + insert + json.substr(open + 1);
}

inline std::string quoted(const std::string& s)
{
    std::string out = "\"";
    for (char c : s) {
        if (c == '"' || c == '\\') { out += '\\'; out += c; }
        else if (c == '\n')        { out += "\\n"; }
        else                       { out += c; }
    }
    out += "\"";
    return out;
}

} // namespace jeemo
