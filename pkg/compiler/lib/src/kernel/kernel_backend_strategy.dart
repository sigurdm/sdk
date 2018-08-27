// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.kernel.backend_strategy;

import 'package:kernel/ast.dart' as ir;

import '../backend_strategy.dart';
import '../common.dart';
import '../common/codegen.dart' show CodegenRegistry, CodegenWorkItem;
import '../common/tasks.dart';
import '../compiler.dart';
import '../elements/entities.dart';
import '../elements/entity_utils.dart' as utils;
import '../enqueue.dart';
import '../js_backend/backend.dart';
import '../js_emitter/sorter.dart';
import '../js_model/js_strategy.dart';
import '../js_model/locals.dart';
import '../kernel/element_map.dart';
import '../native/behavior.dart';
import '../options.dart';
import '../ssa/builder_kernel.dart';
import '../ssa/nodes.dart';
import '../ssa/ssa.dart';
import '../ssa/types.dart';
import '../types/abstract_value_domain.dart';
import '../types/types.dart';
import '../universe/selector.dart';
import '../universe/world_impact.dart';
import '../world.dart';

/// A backend strategy based on Kernel IR nodes.
abstract class KernelBackendStrategy implements BackendStrategy {
  KernelToElementMapForBuilding get elementMap;
  GlobalLocalsMap get globalLocalsMapForTesting;

  factory KernelBackendStrategy(Compiler compiler) {
    return new JsBackendStrategy(compiler);
  }
}

class KernelCodegenWorkItemBuilder implements WorkItemBuilder {
  final JavaScriptBackend _backend;
  final JClosedWorld _closedWorld;
  final GlobalTypeInferenceResults _globalInferenceResults;

  KernelCodegenWorkItemBuilder(
      this._backend, this._closedWorld, this._globalInferenceResults);

  CompilerOptions get _options => _backend.compiler.options;

  @override
  CodegenWorkItem createWorkItem(MemberEntity entity) {
    if (entity.isAbstract) return null;

    // Codegen inlines field initializers. It only needs to generate
    // code for checked setters.
    if (entity.isField && entity.isInstanceMember) {
      if (!_options.parameterCheckPolicy.isEmitted ||
          entity.enclosingClass.isClosure) {
        return null;
      }
    }

    return new KernelCodegenWorkItem(
        _backend, _closedWorld, _globalInferenceResults, entity);
  }
}

class KernelCodegenWorkItem extends CodegenWorkItem {
  final JavaScriptBackend _backend;
  final JClosedWorld _closedWorld;
  final MemberEntity element;
  final CodegenRegistry registry;
  final GlobalTypeInferenceResults _globalInferenceResults;

  KernelCodegenWorkItem(this._backend, this._closedWorld,
      this._globalInferenceResults, this.element)
      : registry =
            new CodegenRegistry(_closedWorld.elementEnvironment, element);

  @override
  WorldImpact run() {
    return _backend.codegen(this, _closedWorld, _globalInferenceResults);
  }
}

/// Task for building SSA from kernel IR loaded from .dill.
class KernelSsaBuilder implements SsaBuilder {
  final CompilerTask task;
  final Compiler _compiler;
  final KernelToElementMapForBuilding _elementMap;
  final GlobalLocalsMap _globalLocalsMap;

  KernelSsaBuilder(
      this.task, this._compiler, this._elementMap, this._globalLocalsMap);

  @override
  HGraph build(CodegenWorkItem work, JClosedWorld closedWorld,
      GlobalTypeInferenceResults results) {
    return task.measure(() {
      KernelSsaGraphBuilder builder = new KernelSsaGraphBuilder(
          work.element,
          _elementMap.getMemberThisType(work.element),
          _compiler,
          _elementMap,
          results,
          _globalLocalsMap,
          closedWorld,
          _compiler.codegenWorldBuilder,
          work.registry,
          _compiler.backendStrategy.closureDataLookup,
          _compiler.backend.emitter.nativeEmitter,
          _compiler.backend.sourceInformationStrategy);
      return builder.build();
    });
  }
}

class KernelToTypeInferenceMapImpl implements KernelToTypeInferenceMap {
  final GlobalTypeInferenceResults _globalInferenceResults;
  GlobalTypeInferenceElementResult _targetResults;

  KernelToTypeInferenceMapImpl(
      MemberEntity target, this._globalInferenceResults) {
    _targetResults = _resultOf(target);
  }

  GlobalTypeInferenceElementResult _resultOf(MemberEntity e) =>
      _globalInferenceResults
          .resultOfMember(e is ConstructorBodyEntity ? e.constructor : e);

  AbstractValue getReturnTypeOf(FunctionEntity function) {
    return AbstractValueFactory.inferredReturnTypeForElement(
        function, _globalInferenceResults);
  }

  AbstractValue receiverTypeOfInvocation(
      ir.MethodInvocation node, AbstractValueDomain abstractValueDomain) {
    return _targetResults.typeOfSend(node);
  }

  AbstractValue receiverTypeOfGet(ir.PropertyGet node) {
    return _targetResults.typeOfSend(node);
  }

  AbstractValue receiverTypeOfDirectGet(ir.DirectPropertyGet node) {
    return _targetResults.typeOfSend(node);
  }

  AbstractValue receiverTypeOfSet(
      ir.PropertySet node, AbstractValueDomain abstractValueDomain) {
    return _targetResults.typeOfSend(node);
  }

  AbstractValue typeOfListLiteral(MemberEntity owner,
      ir.ListLiteral listLiteral, AbstractValueDomain abstractValueDomain) {
    return _resultOf(owner).typeOfListLiteral(listLiteral) ??
        abstractValueDomain.dynamicType;
  }

  AbstractValue typeOfIterator(ir.ForInStatement node) {
    return _targetResults.typeOfIterator(node);
  }

  AbstractValue typeOfIteratorCurrent(ir.ForInStatement node) {
    return _targetResults.typeOfIteratorCurrent(node);
  }

  AbstractValue typeOfIteratorMoveNext(ir.ForInStatement node) {
    return _targetResults.typeOfIteratorMoveNext(node);
  }

  bool isJsIndexableIterator(
      ir.ForInStatement node, AbstractValueDomain abstractValueDomain) {
    AbstractValue mask = typeOfIterator(node);
    return abstractValueDomain.isJsIndexableAndIterable(mask);
  }

  AbstractValue inferredIndexType(ir.ForInStatement node) {
    return AbstractValueFactory.inferredTypeForSelector(
        new Selector.index(), typeOfIterator(node), _globalInferenceResults);
  }

  AbstractValue getInferredTypeOf(MemberEntity member) {
    return AbstractValueFactory.inferredTypeForMember(
        member, _globalInferenceResults);
  }

  AbstractValue getInferredTypeOfParameter(Local parameter) {
    return AbstractValueFactory.inferredTypeForParameter(
        parameter, _globalInferenceResults);
  }

  AbstractValue selectorTypeOf(Selector selector, AbstractValue mask) {
    return AbstractValueFactory.inferredTypeForSelector(
        selector, mask, _globalInferenceResults);
  }

  AbstractValue typeFromNativeBehavior(
      NativeBehavior nativeBehavior, JClosedWorld closedWorld) {
    return AbstractValueFactory.fromNativeBehavior(nativeBehavior, closedWorld);
  }
}

class KernelSorter implements Sorter {
  final KernelToElementMapForBuilding elementMap;

  KernelSorter(this.elementMap);

  int _compareLibraries(LibraryEntity a, LibraryEntity b) {
    return utils.compareLibrariesUris(a.canonicalUri, b.canonicalUri);
  }

  int _compareSourceSpans(Entity entity1, SourceSpan sourceSpan1,
      Entity entity2, SourceSpan sourceSpan2) {
    int r = utils.compareSourceUris(sourceSpan1.uri, sourceSpan2.uri);
    if (r != 0) return r;
    return utils.compareEntities(
        entity1, sourceSpan1.begin, null, entity2, sourceSpan2.begin, null);
  }

  @override
  Iterable<LibraryEntity> sortLibraries(Iterable<LibraryEntity> libraries) {
    return libraries.toList()..sort(_compareLibraries);
  }

  @override
  Iterable<T> sortMembers<T extends MemberEntity>(Iterable<T> members) {
    return members.toList()..sort(compareMembersByLocation);
  }

  @override
  Iterable<ClassEntity> sortClasses(Iterable<ClassEntity> classes) {
    List<ClassEntity> regularClasses = <ClassEntity>[];
    List<ClassEntity> unnamedMixins = <ClassEntity>[];
    for (ClassEntity cls in classes) {
      if (elementMap.elementEnvironment.isUnnamedMixinApplication(cls)) {
        unnamedMixins.add(cls);
      } else {
        regularClasses.add(cls);
      }
    }
    List<ClassEntity> sorted = <ClassEntity>[];
    regularClasses.sort(compareClassesByLocation);
    sorted.addAll(regularClasses);
    unnamedMixins.sort((a, b) {
      int result = _compareLibraries(a.library, b.library);
      if (result != 0) return result;
      result = a.name.compareTo(b.name);
      assert(result != 0,
          failedAt(a, "Multiple mixins named ${a.name}: $a vs $b."));
      return result;
    });
    sorted.addAll(unnamedMixins);
    return sorted;
  }

  @override
  Iterable<TypedefEntity> sortTypedefs(Iterable<TypedefEntity> typedefs) {
    // TODO(redemption): Support this.
    assert(typedefs.isEmpty);
    return typedefs;
  }

  @override
  int compareLibrariesByLocation(LibraryEntity a, LibraryEntity b) {
    return _compareLibraries(a, b);
  }

  @override
  int compareClassesByLocation(ClassEntity a, ClassEntity b) {
    int r = _compareLibraries(a.library, b.library);
    if (r != 0) return r;
    ClassDefinition definition1 = elementMap.getClassDefinition(a);
    ClassDefinition definition2 = elementMap.getClassDefinition(b);
    return _compareSourceSpans(
        a, definition1.location, b, definition2.location);
  }

  @override
  int compareTypedefsByLocation(TypedefEntity a, TypedefEntity b) {
    // TODO(redemption): Support this.
    failedAt(a, 'KernelSorter.compareTypedefsByLocation unimplemented');
    return 0;
  }

  @override
  int compareMembersByLocation(MemberEntity a, MemberEntity b) {
    int r = _compareLibraries(a.library, b.library);
    if (r != 0) return r;
    MemberDefinition definition1 = elementMap.getMemberDefinition(a);
    MemberDefinition definition2 = elementMap.getMemberDefinition(b);
    return _compareSourceSpans(
        a, definition1.location, b, definition2.location);
  }
}
