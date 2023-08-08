// Code generated by mockery v2.22.1. DO NOT EDIT.

package mocks

import (
	context "context"

	common "github.com/ethereum/go-ethereum/common"

	mock "github.com/stretchr/testify/mock"

	txmgrtypes "github.com/smartcontractkit/chainlink/v2/common/txmgr/types"

	types "github.com/smartcontractkit/chainlink/v2/core/chains/evm/types"
)

// HeadBroadcaster is an autogenerated mock type for the HeadBroadcaster type
type HeadBroadcaster struct {
	mock.Mock
}

// BroadcastNewLongestChain provides a mock function with given fields: head
func (_m *HeadBroadcaster) BroadcastNewLongestChain(head *types.Head) {
	_m.Called(head)
}

// Close provides a mock function with given fields:
func (_m *HeadBroadcaster) Close() error {
	ret := _m.Called()

	var r0 error
	if rf, ok := ret.Get(0).(func() error); ok {
		r0 = rf()
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// HealthReport provides a mock function with given fields:
func (_m *HeadBroadcaster) HealthReport() map[string]error {
	ret := _m.Called()

	var r0 map[string]error
	if rf, ok := ret.Get(0).(func() map[string]error); ok {
		r0 = rf()
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(map[string]error)
		}
	}

	return r0
}

// Name provides a mock function with given fields:
func (_m *HeadBroadcaster) Name() string {
	ret := _m.Called()

	var r0 string
	if rf, ok := ret.Get(0).(func() string); ok {
		r0 = rf()
	} else {
		r0 = ret.Get(0).(string)
	}

	return r0
}

// Ready provides a mock function with given fields:
func (_m *HeadBroadcaster) Ready() error {
	ret := _m.Called()

	var r0 error
	if rf, ok := ret.Get(0).(func() error); ok {
		r0 = rf()
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// Start provides a mock function with given fields: _a0
func (_m *HeadBroadcaster) Start(_a0 context.Context) error {
	ret := _m.Called(_a0)

	var r0 error
	if rf, ok := ret.Get(0).(func(context.Context) error); ok {
		r0 = rf(_a0)
	} else {
		r0 = ret.Error(0)
	}

	return r0
}

// Subscribe provides a mock function with given fields: callback
func (_m *HeadBroadcaster) Subscribe(callback txmgrtypes.HeadTrackable[*types.Head, common.Hash]) (*types.Head, func()) {
	ret := _m.Called(callback)

	var r0 *types.Head
	var r1 func()
	if rf, ok := ret.Get(0).(func(txmgrtypes.HeadTrackable[*types.Head, common.Hash]) (*types.Head, func())); ok {
		return rf(callback)
	}
	if rf, ok := ret.Get(0).(func(txmgrtypes.HeadTrackable[*types.Head, common.Hash]) *types.Head); ok {
		r0 = rf(callback)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*types.Head)
		}
	}

	if rf, ok := ret.Get(1).(func(txmgrtypes.HeadTrackable[*types.Head, common.Hash]) func()); ok {
		r1 = rf(callback)
	} else {
		if ret.Get(1) != nil {
			r1 = ret.Get(1).(func())
		}
	}

	return r0, r1
}

type mockConstructorTestingTNewHeadBroadcaster interface {
	mock.TestingT
	Cleanup(func())
}

// NewHeadBroadcaster creates a new instance of HeadBroadcaster. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
func NewHeadBroadcaster(t mockConstructorTestingTNewHeadBroadcaster) *HeadBroadcaster {
	mock := &HeadBroadcaster{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}