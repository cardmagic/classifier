# Test Coverage Audit Report

**Date:** 2025-12-27
**Branch:** audit/spec-coverage
**Issue:** #48

## Summary

| Metric | Current | Target |
|--------|---------|--------|
| Line Coverage | 88.06% | 95%+ |
| Branch Coverage | 67.92% | 85%+ |

## Coverage by File

| File | Line Coverage | Notes |
|------|---------------|-------|
| classifier.rb | 100% | ✅ Complete |
| string.rb | 100% | ✅ Complete |
| word_list.rb | 100% | ✅ Complete |
| word_hash.rb | 95.7% | Missing: `without_punctuation` |
| content_node.rb | 90.9% | Missing: GSL branch |
| lsi.rb | 89.2% | Multiple gaps |
| summary.rb | 87.5% | Edge cases |
| vector.rb | 84.1% | `magnitude`/`normalize` not directly tested |
| bayes.rb | 80.6% | **`untrain` method completely untested** |

## Critical Gaps Identified

### 1. Bayes Classifier (`lib/classifier/bayes.rb`)

**Untested: `untrain` method (lines 44-60)**

The `untrain` method reverses training by removing word frequencies. This is a critical method with no test coverage.

```ruby
def untrain(category, text)
  # ... completely untested
end
```

**Missing tests:**
- [ ] Basic untrain functionality
- [ ] Untrain via dynamic method (`untrain_category_name`)
- [ ] Untrain effect on classification
- [ ] Edge case: untrain more than trained
- [ ] Edge case: untrain non-existent words

### 2. LSI Classifier (`lib/classifier/lsi.rb`)

**Untested: `remove_item` method (lines 98-103)**
```ruby
def remove_item(item)
  return unless @items.key?(item)
  @items.delete(item)
  @version += 1
end
```

**Untested: `items` method (line 107)**
```ruby
def items
  @items.keys
end
```

**Missing tests:**
- [ ] `remove_item` basic functionality
- [ ] `remove_item` non-existent item (no-op)
- [ ] `remove_item` triggers rebuild need
- [ ] `items` returns indexed items
- [ ] GSL vs native Ruby parity (requires GSL gem)

### 3. Extensions

**`word_hash.rb` - `without_punctuation` (line 15)**
- Method exists but not directly tested

**`vector.rb` - `magnitude` and `normalize` (lines 18-33)**
- Used internally but no direct unit tests
- Edge cases: zero vector, single element

### 4. Edge Cases Not Tested

**Bayes:**
- [ ] Empty string classification
- [ ] Unicode text handling
- [ ] Special characters only
- [ ] Very long text
- [ ] Single word classification

**LSI:**
- [ ] Empty index operations
- [ ] Single item index
- [ ] Classification with no categories
- [ ] Very large document sets

**Serialization:**
- [ ] Marshal dump/load with GSL (when available)
- [ ] Cross-version compatibility

## Follow-up Issues Created

- #50 - Add tests for Bayes#untrain method
- #51 - Add tests for LSI#remove_item and LSI#items methods
- #52 - Add edge case tests for text handling

## Recommendations

### Immediate (High Priority)
1. Add tests for `Bayes#untrain` - critical missing coverage (#50)
2. Add tests for `LSI#remove_item` and `LSI#items` (#51)
3. Add edge case tests for empty/unicode strings (#52)

### Short-term (Medium Priority)
4. Add direct unit tests for vector extensions
5. Test `without_punctuation` method
6. Add integration tests for serialization

### Long-term (Low Priority)
7. Set up CI matrix to test with/without GSL
8. Add performance benchmarks
9. Consider property-based testing for edge cases

## Test Files to Create/Modify

1. `test/bayes/untrain_test.rb` - New file for untrain tests
2. `test/bayes/edge_cases_test.rb` - New file for edge cases
3. `test/lsi/lsi_test.rb` - Add remove_item, items tests
4. `test/extensions/vector_test.rb` - New file for vector tests
5. `test/extensions/word_hash_test.rb` - Add without_punctuation test
