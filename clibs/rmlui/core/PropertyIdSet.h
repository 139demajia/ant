#pragma once

#include <core/ID.h>
#include <assert.h>
#include <bit>
#include <cstring>
#include <iterator>
#include <type_traits>


namespace Rml {

template <typename T, size_t N>
class enumset {
private:
    static_assert(std::is_enum_v<T>);
    using BitT = std::conditional_t<N <= sizeof(unsigned long) * CHAR_BIT, unsigned long, unsigned long long>;
    static constexpr ptrdiff_t Bitsperword = CHAR_BIT * sizeof(BitT);
    BitT data[(N == 0) ? 1 : ((N - 1) / Bitsperword) + 1];
public:
    class const_iterator {
    public:
        using iterator_category = std::forward_iterator_tag;
        constexpr explicit const_iterator(const enumset& set)
            : index { static_cast<size_t>(-1) }
            , set { set }
        {}
        constexpr const_iterator operator++() {
            seek_next();
            return *this;
        }
        constexpr const_iterator operator++(int) {
            const_iterator prev_this = *this;
            seek_next();
            return prev_this;
        }
        constexpr T operator*() const { return static_cast<T>(index); }
        constexpr bool operator==(const const_iterator& rhs) const {
            return (index == rhs.index) && (set == rhs.set);
        }
        constexpr bool operator!=(const const_iterator& rhs) const {
            return !operator==(rhs);
        }
        friend const_iterator enumset::begin() const;
        friend const_iterator enumset::end() const;
    protected:
        size_t index;
    private:
        constexpr void seek_next() {
            while (++(index) < N) {
                if (set.contains((T)index) == true) {
                    break;
                }
            }
        }
        const enumset& set;
    };

    constexpr enumset() noexcept : data() {}

    constexpr void insert(T v) {
        size_t pos = (size_t)v;
        assert(pos < N);
        data[pos / Bitsperword] |= BitT{1} << pos % Bitsperword;
    }
    constexpr void erase(T v) {
        size_t pos = (size_t)v;
        assert(pos < N);
        data[pos / Bitsperword] &= ~(BitT{1} << pos % Bitsperword);
    }
    constexpr void clear() {
        if (std::is_constant_evaluated()) {
            for (auto& e : data) {
                e = 0;
            }
        } else {
            std::memset(&data, 0, sizeof(data));
        }
    }
    constexpr bool empty() const {
        for (size_t i = 0; i < sizeof(data)/sizeof(data[0]); ++i) {
            if (data[i] != 0) {
                return false;
            }
        }
        return true;
    }
    constexpr bool contains(T v) const {
        size_t pos = (size_t)v;
        assert(pos < N);
        return (data[pos / Bitsperword] & (BitT{1} << pos % Bitsperword)) != 0;
    }
    constexpr size_t size() const {
        size_t n = 0;
        for (size_t i = 0; i < sizeof(data)/sizeof(data[0]); ++i) {
            n += std::popcount(data[i]);
        }
        return n;
    }
    constexpr enumset& operator&=(const enumset& other) {
        for (size_t i = 0; i < sizeof(data)/sizeof(data[0]); ++i) {
            data[i] &= other.data[i];
        }
        return *this;
    }
    constexpr enumset& operator|=(const enumset& other) {
        for (size_t i = 0; i < sizeof(data)/sizeof(data[0]); ++i) {
            data[i] |= other.data[i];
        }
        return *this;
    }
    constexpr bool operator==(const enumset& other) const {
        for (size_t i = 0; i < sizeof(data)/sizeof(data[0]); ++i) {
            if (data[i] != other.data[i]) {
                return false;
            }
        }
        return true;
    }
    constexpr enumset operator&(const enumset& other) const {
        enumset set = *this;
        set &= other;
        return set;
    }
    constexpr const_iterator begin() const {
        const_iterator iterator{ *this };
        iterator.seek_next();
        return iterator;
    }
    constexpr const_iterator end() const {
        const_iterator iterator{ *this };
        iterator.index = N;
        return iterator;
    }
};

using PropertyIdSet = enumset<PropertyId, size_t(PropertyId::NumDefinedIds)>;

}
