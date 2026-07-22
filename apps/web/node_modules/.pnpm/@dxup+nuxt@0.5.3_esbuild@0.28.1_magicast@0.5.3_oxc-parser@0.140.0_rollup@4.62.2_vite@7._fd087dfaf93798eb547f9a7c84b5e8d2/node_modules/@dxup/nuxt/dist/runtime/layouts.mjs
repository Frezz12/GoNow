import { defineComponent, h, inject, provide, shallowRef } from "vue";
import { NuxtLayout } from "#build/dxup/layouts.mjs";
//#region src/module/named-layout-slots/runtime/layouts.ts
const injectionKey = Symbol.for("dxup:layout-slots");
var layouts_default = defineComponent((props, ctx) => {
	const slots = shallowRef({});
	let resolveReady;
	provide(injectionKey, {
		slots,
		ready: new Promise((resolve) => {
			resolveReady = resolve;
		}),
		set(value) {
			slots.value = value;
			resolveReady?.();
		}
	});
	return () => h(NuxtLayout, props, ctx.slots);
});
const LayoutSlot = defineComponent({
	props: { name: {
		type: String,
		required: true
	} },
	setup(props, ctx) {
		const { slots, ready } = inject(injectionKey);
		const render = () => slots.value[props.name]?.(ctx.attrs);
		if (import.meta.server && !slots.value[props.name]) return ready.then(() => render);
		return render;
	}
});
const LayoutSlotsForward = defineComponent((props, ctx) => {
	const { set } = inject(injectionKey);
	set(ctx.slots);
	return () => ctx.slots.default?.();
});
//#endregion
export { LayoutSlot, LayoutSlotsForward, layouts_default as default };
