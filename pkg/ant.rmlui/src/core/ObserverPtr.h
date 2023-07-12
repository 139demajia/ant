#pragma once

#include <utility>
#include <type_traits>
#include <assert.h>

namespace Rml {

struct ObserverPtrBlock {
	int num_observers;
	void* pointed_to_object;
};

inline void DeallocateObserverPtrBlockIfEmpty(ObserverPtrBlock* block) {
	assert(block->num_observers >= 0);
	if (block->num_observers == 0 && block->pointed_to_object == nullptr) {
		delete block;
	}
}


template<typename T>
class EnableObserverPtr;


/**
	Observer pointer.

	Holds a weak reference to an object owned by someone else. Can tell whether or not the pointed to object has been destroyed.

	Usage: Given a class T, derive from EnableObserverPtr<T>. Then, we can use the observer pointer as follows:

		auto object = std::make_unique<T>();
		ObserverPtr<T> observer_ptr = object->GetObserverPtr();
		// ...
		if(obserer_ptr) { 
			// Will only enter if object is still alive.
			observer_ptr->do_a_thing(); 
		} 

	Note: Not thread safe.
 */

template<typename T>
class ObserverPtr {
public:
	ObserverPtr() noexcept : block(nullptr) {}
	ObserverPtr(std::nullptr_t) noexcept : block(nullptr) {}
	~ObserverPtr() noexcept {
		reset(); 
	}

	// Copy
	ObserverPtr(const ObserverPtr<T>& other) noexcept : block(other.block) {
		if (block)
			block->num_observers += 1;
	}
	ObserverPtr<T>& operator=(const ObserverPtr<T>& other) noexcept {
		reset();
		block = other.block;
		if (block)
			block->num_observers += 1;
		return *this;
	}

	// Move
	ObserverPtr(ObserverPtr<T>&& other) noexcept : block(std::exchange(other.block, nullptr)) {}
	ObserverPtr<T>& operator=(ObserverPtr<T>&& other) noexcept {
		reset();
		block = std::exchange(other.block, nullptr);
		return *this;
	}

	// Returns true if we can dereference the pointer.
	explicit operator bool() const noexcept { return block && block->pointed_to_object; }

	// Comparison operators return true when they point to the same object, or they are both nullptr or expired.
	bool operator==(const T* other) const noexcept { return get() == other; }
	bool operator==(const ObserverPtr<T>& other) const noexcept { return get() == other.get(); }

	// Retrieve the pointer to the observed object if we have one and it's still alive.
	T* get() const noexcept {
		return block ? static_cast<T*>(block->pointed_to_object) : nullptr;
	}
	// Dereference the pointed to object.
	T* operator->() const noexcept {
		return static_cast<T*>(block->pointed_to_object);
	}

	// Reset the pointer so that it does not point to anything.
	// When the pointed to object and all observer pointers to it have been destroyed, it will deallocate the block.
	void reset() noexcept {
		if (block)
		{
			block->num_observers -= 1;
			DeallocateObserverPtrBlockIfEmpty(block);
			block = nullptr;
		}
	}

private:
	friend class Rml::EnableObserverPtr<T>;

	explicit ObserverPtr(ObserverPtrBlock* block) noexcept : block(block) {
		if (block)
			block->num_observers += 1;
	}

	ObserverPtrBlock* block;
};



template<typename T>
class EnableObserverPtr {
public:
	ObserverPtr<T> GetObserverPtr() {
		InitializeBlock();
		return ObserverPtr<T>(block);
	}

protected:
	EnableObserverPtr() noexcept {
		static_assert(std::is_base_of_v<EnableObserverPtr<T>, T>, "T must derive from EnableObserverPtr<T>.");
	}

	~EnableObserverPtr() noexcept {
		if (block) {
			block->pointed_to_object = nullptr;
			DeallocateObserverPtrBlockIfEmpty(block);
		}
	}

	EnableObserverPtr(const EnableObserverPtr<T>&) = delete;
	EnableObserverPtr(EnableObserverPtr<T>&&) noexcept = delete;
	EnableObserverPtr<T>& operator=(const EnableObserverPtr<T>&) = delete;
	EnableObserverPtr<T>& operator=(EnableObserverPtr<T>&&) = delete;

private:
	inline void InitializeBlock() {
		if (!block) {
			block = new ObserverPtrBlock;
			block->num_observers = 0;
			block->pointed_to_object = static_cast<void*>(static_cast<T*>(this));
		}
	}
	ObserverPtrBlock* block = nullptr;
};


}
