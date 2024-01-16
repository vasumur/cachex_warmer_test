import {
  PHX_COMPONENT,
  PHX_DISABLE_WITH,
  PHX_FEEDBACK_FOR,
  PHX_PRUNE,
  PHX_ROOT_ID,
  PHX_SESSION,
  PHX_SKIP,
  PHX_MAGIC_ID,
  PHX_STATIC,
  PHX_TRIGGER_ACTION,
  PHX_UPDATE,
  PHX_STREAM,
  PHX_STREAM_REF,
  PHX_VIEWPORT_TOP,
  PHX_VIEWPORT_BOTTOM,
} from "./constants"

import {
  detectDuplicateIds,
  isCid
} from "./utils"

import DOM from "./dom"
import DOMPostMorphRestorer from "./dom_post_morph_restorer"
import morphdom from "morphdom"

export default class DOMPatch {
  static patchEl(fromEl, toEl, activeElement){
    morphdom(fromEl, toEl, {
      childrenOnly: false,
      onBeforeElUpdated: (fromEl, toEl) => {
        if(activeElement && activeElement.isSameNode(fromEl) && DOM.isFormInput(fromEl)){
          DOM.mergeFocusedInput(fromEl, toEl)
          return false
        }
      }
    })
  }

  constructor(view, container, id, html, streams, targetCID){
    this.view = view
    this.liveSocket = view.liveSocket
    this.container = container
    this.id = id
    this.rootID = view.root.id
    this.html = html
    this.streams = streams
    this.streamInserts = {}
    this.targetCID = targetCID
    this.cidPatch = isCid(this.targetCID)
    this.pendingRemoves = []
    this.phxRemove = this.liveSocket.binding("remove")
    this.callbacks = {
      beforeadded: [], beforeupdated: [], beforephxChildAdded: [],
      afteradded: [], afterupdated: [], afterdiscarded: [], afterphxChildAdded: [],
      aftertransitionsDiscarded: []
    }
  }

  before(kind, callback){ this.callbacks[`before${kind}`].push(callback) }
  after(kind, callback){ this.callbacks[`after${kind}`].push(callback) }

  trackBefore(kind, ...args){
    this.callbacks[`before${kind}`].forEach(callback => callback(...args))
  }

  trackAfter(kind, ...args){
    this.callbacks[`after${kind}`].forEach(callback => callback(...args))
  }

  markPrunableContentForRemoval(){
    let phxUpdate = this.liveSocket.binding(PHX_UPDATE)
    DOM.all(this.container, `[${phxUpdate}=${PHX_STREAM}]`, el => el.innerHTML = "")
    DOM.all(this.container, `[${phxUpdate}=append] > *, [${phxUpdate}=prepend] > *`, el => {
      el.setAttribute(PHX_PRUNE, "")
    })
  }

  perform(isJoinPatch){
    let {view, liveSocket, container, html} = this
    let targetContainer = this.isCIDPatch() ? this.targetCIDContainer(html) : container
    if(this.isCIDPatch() && !targetContainer){ return }

    let focused = liveSocket.getActiveElement()
    let {selectionStart, selectionEnd} = focused && DOM.hasSelectionRange(focused) ? focused : {}
    let phxUpdate = liveSocket.binding(PHX_UPDATE)
    let phxFeedbackFor = liveSocket.binding(PHX_FEEDBACK_FOR)
    let disableWith = liveSocket.binding(PHX_DISABLE_WITH)
    let phxViewportTop = liveSocket.binding(PHX_VIEWPORT_TOP)
    let phxViewportBottom = liveSocket.binding(PHX_VIEWPORT_BOTTOM)
    let phxTriggerExternal = liveSocket.binding(PHX_TRIGGER_ACTION)
    let added = []
    let trackedInputs = []
    let updates = []
    let appendPrependUpdates = []

    let externalFormTriggered = null

    this.trackBefore("added", container)
    this.trackBefore("updated", container, container)

    liveSocket.time("morphdom", () => {
      this.streams.forEach(([ref, inserts, deleteIds, reset]) => {
        Object.entries(inserts).forEach(([key, [streamAt, limit]]) => {
          this.streamInserts[key] = {ref, streamAt, limit, resetKept: false}
        })
        if(reset !== undefined){
          DOM.all(container, `[${PHX_STREAM_REF}="${ref}"]`, child => {
            if(inserts[child.id]){
              this.streamInserts[child.id].resetKept = true
            } else {
              this.removeStreamChildElement(child)
            }
          })
        }
        deleteIds.forEach(id => {
          let child = container.querySelector(`[id="${id}"]`)
          if(child){ this.removeStreamChildElement(child) }
        })
      })

      morphdom(targetContainer, html, {
        childrenOnly: targetContainer.getAttribute(PHX_COMPONENT) === null,
        getNodeKey: (node) => {
          if(DOM.isPhxDestroyed(node)){ return null }
          // If we have a join patch, then by definition there was no PHX_MAGIC_ID.
          // This is important to reduce the amount of elements morphdom discards.
          if(isJoinPatch){ return node.id }
          return node.id || (node.getAttribute && node.getAttribute(PHX_MAGIC_ID))
        },
        // skip indexing from children when container is stream
        skipFromChildren: (from) => { return from.getAttribute(phxUpdate) === PHX_STREAM },
        // tell morphdom how to add a child
        addChild: (parent, child) => {
          let {ref, streamAt, limit} = this.getStreamInsert(child)
          if(ref === undefined) { return parent.appendChild(child) }

          DOM.putSticky(child, PHX_STREAM_REF, el => el.setAttribute(PHX_STREAM_REF, ref))

          // streaming
          if(streamAt === 0){
            parent.insertAdjacentElement("afterbegin", child)
          } else if(streamAt === -1){
            parent.appendChild(child)
          } else if(streamAt > 0){
            let sibling = Array.from(parent.children)[streamAt]
            parent.insertBefore(child, sibling)
          }
          let children = limit !== null && Array.from(parent.children)
          let childrenToRemove = []
          if(limit && limit < 0 && children.length > limit * -1){
            childrenToRemove = children.slice(0, children.length + limit)
          } else if(limit && limit >= 0 && children.length > limit){
            childrenToRemove = children.slice(limit)
          }
          childrenToRemove.forEach(removeChild => {
            // do not remove child as part of limit if we are re-adding it
            if(!this.streamInserts[removeChild.id]){
              this.removeStreamChildElement(removeChild)
            }
          })
        },
        onBeforeNodeAdded: (el) => {
          DOM.maybeAddPrivateHooks(el, phxViewportTop, phxViewportBottom)
          this.trackBefore("added", el)
          return el
        },
        onNodeAdded: (el) => {
          if(el.getAttribute){ this.maybeReOrderStream(el) }

          // hack to fix Safari handling of img srcset and video tags
          if(el instanceof HTMLImageElement && el.srcset){
            el.srcset = el.srcset
          } else if(el instanceof HTMLVideoElement && el.autoplay){
            el.play()
          }
          if(DOM.isNowTriggerFormExternal(el, phxTriggerExternal)){
            externalFormTriggered = el
          }

          if(el.getAttribute && el.getAttribute("name") && DOM.isFormInput(el)){
            trackedInputs.push(el)
          }
          // nested view handling
          if((DOM.isPhxChild(el) && view.ownsElement(el)) || DOM.isPhxSticky(el) && view.ownsElement(el.parentNode)){
            this.trackAfter("phxChildAdded", el)
          }
          added.push(el)
        },
        onBeforeElChildrenUpdated: (fromEl, toEl) => {
          // before we update the children, we need to set existing stream children
          // into the new order from the server if they were kept during a stream reset
          if(fromEl.getAttribute(phxUpdate) === PHX_STREAM){
            let toIds = Array.from(toEl.children).map(child => child.id)
            Array.from(fromEl.children).filter(child => {
              let {resetKept} = this.getStreamInsert(child)
              return resetKept
            }).forEach((child) => {
              this.streamInserts[child.id].streamAt = toIds.indexOf(child.id)
            })
          }
        },
        onNodeDiscarded: (el) => this.onNodeDiscarded(el),
        onBeforeNodeDiscarded: (el) => {
          if(el.getAttribute && el.getAttribute(PHX_PRUNE) !== null){ return true }
          if(el.parentElement !== null && el.id &&
            DOM.isPhxUpdate(el.parentElement, phxUpdate, [PHX_STREAM, "append", "prepend"])){
            return false
          }
          if(this.maybePendingRemove(el)){ return false }
          if(this.skipCIDSibling(el)){ return false }

          return true
        },
        onElUpdated: (el) => {
          if(DOM.isNowTriggerFormExternal(el, phxTriggerExternal)){
            externalFormTriggered = el
          }
          updates.push(el)
          this.maybeReOrderStream(el)
        },
        onBeforeElUpdated: (fromEl, toEl) => {
          DOM.maybeAddPrivateHooks(toEl, phxViewportTop, phxViewportBottom)
          DOM.cleanChildNodes(toEl, phxUpdate)
          if(this.skipCIDSibling(toEl)){ return false }
          if(DOM.isPhxSticky(fromEl)){ return false }
          if(DOM.isIgnored(fromEl, phxUpdate) || (fromEl.form && fromEl.form.isSameNode(externalFormTriggered))){
            this.trackBefore("updated", fromEl, toEl)
            DOM.mergeAttrs(fromEl, toEl, {isIgnored: true})
            updates.push(fromEl)
            DOM.applyStickyOperations(fromEl)
            return false
          }
          if(fromEl.type === "number" && (fromEl.validity && fromEl.validity.badInput)){ return false }
          if(!DOM.syncPendingRef(fromEl, toEl, disableWith)){
            if(DOM.isUploadInput(fromEl)){
              this.trackBefore("updated", fromEl, toEl)
              updates.push(fromEl)
            }
            DOM.applyStickyOperations(fromEl)
            return false
          }

          // nested view handling
          if(DOM.isPhxChild(toEl)){
            let prevSession = fromEl.getAttribute(PHX_SESSION)
            DOM.mergeAttrs(fromEl, toEl, {exclude: [PHX_STATIC]})
            if(prevSession !== ""){ fromEl.setAttribute(PHX_SESSION, prevSession) }
            fromEl.setAttribute(PHX_ROOT_ID, this.rootID)
            DOM.applyStickyOperations(fromEl)
            return false
          }

          // input handling
          DOM.copyPrivates(toEl, fromEl)

          let isFocusedFormEl = focused && fromEl.isSameNode(focused) && DOM.isFormInput(fromEl)
          if(isFocusedFormEl && fromEl.type !== "hidden"){
            this.trackBefore("updated", fromEl, toEl)
            DOM.mergeFocusedInput(fromEl, toEl)
            DOM.syncAttrsToProps(fromEl)
            updates.push(fromEl)
            DOM.applyStickyOperations(fromEl)
            trackedInputs.push(fromEl)
            return false
          } else {
            if(DOM.isPhxUpdate(toEl, phxUpdate, ["append", "prepend"])){
              appendPrependUpdates.push(new DOMPostMorphRestorer(fromEl, toEl, toEl.getAttribute(phxUpdate)))
            }

            DOM.syncAttrsToProps(toEl)
            DOM.applyStickyOperations(toEl)
            if(toEl.getAttribute("name") && DOM.isFormInput(toEl)){
              trackedInputs.push(toEl)
            }
            this.trackBefore("updated", fromEl, toEl)
            return true
          }
        }
      })
    })

    if(liveSocket.isDebugEnabled()){ detectDuplicateIds() }

    if(appendPrependUpdates.length > 0){
      liveSocket.time("post-morph append/prepend restoration", () => {
        appendPrependUpdates.forEach(update => update.perform())
      })
    }

    DOM.maybeHideFeedback(targetContainer, trackedInputs, phxFeedbackFor)

    liveSocket.silenceEvents(() => DOM.restoreFocus(focused, selectionStart, selectionEnd))
    DOM.dispatchEvent(document, "phx:update")
    added.forEach(el => this.trackAfter("added", el))
    updates.forEach(el => this.trackAfter("updated", el))

    this.transitionPendingRemoves()

    if(externalFormTriggered){
      liveSocket.unload()
      // use prototype's submit in case there's a form control with name or id of "submit"
      // https://developer.mozilla.org/en-US/docs/Web/API/HTMLFormElement/submit
      Object.getPrototypeOf(externalFormTriggered).submit.call(externalFormTriggered)
    }
    return true
  }

  onNodeDiscarded(el){
    // nested view handling
    if(DOM.isPhxChild(el) || DOM.isPhxSticky(el)){ this.liveSocket.destroyViewByEl(el) }
    this.trackAfter("discarded", el)
  }

  maybePendingRemove(node){
    if(node.getAttribute && node.getAttribute(this.phxRemove) !== null){
      this.pendingRemoves.push(node)
      return true
    } else {
      return false
    }
  }

  removeStreamChildElement(child){
    if(!this.maybePendingRemove(child)){
      child.remove()
      this.onNodeDiscarded(child)
    }
  }

  getStreamInsert(el){
    let insert = el.id ? this.streamInserts[el.id] : {}
    return insert || {}
  }

  maybeReOrderStream(el){
    let {ref, streamAt, limit} = this.getStreamInsert(el)
    if(streamAt === undefined){ return }

    // we need to the PHX_STREAM_REF here as well as addChild is invoked only for parents
    DOM.putSticky(el, PHX_STREAM_REF, el => el.setAttribute(PHX_STREAM_REF, ref))

    if(streamAt === 0){
      el.parentElement.insertBefore(el, el.parentElement.firstElementChild)
    } else if(streamAt > 0){
      let children = Array.from(el.parentElement.children)
      let oldIndex = children.indexOf(el)
      if(streamAt >= children.length - 1){
        el.parentElement.appendChild(el)
      } else {
        let sibling = children[streamAt]
        if(oldIndex > streamAt){
          el.parentElement.insertBefore(el, sibling)
        } else {
          el.parentElement.insertBefore(el, sibling.nextElementSibling)
        }
      }
    }
  }

  transitionPendingRemoves(){
    let {pendingRemoves, liveSocket} = this
    if(pendingRemoves.length > 0){
      liveSocket.transitionRemoves(pendingRemoves)
      liveSocket.requestDOMUpdate(() => {
        pendingRemoves.forEach(el => {
          let child = DOM.firstPhxChild(el)
          if(child){ liveSocket.destroyViewByEl(child) }
          el.remove()
        })
        this.trackAfter("transitionsDiscarded", pendingRemoves)
      })
    }
  }

  isCIDPatch(){ return this.cidPatch }

  skipCIDSibling(el){
    return el.nodeType === Node.ELEMENT_NODE && el.hasAttribute(PHX_SKIP)
  }

  targetCIDContainer(html){
    if(!this.isCIDPatch()){ return }
    let [first, ...rest] = DOM.findComponentNodeList(this.container, this.targetCID)
    if(rest.length === 0 && DOM.childNodeLength(html) === 1){
      return first
    } else {
      return first && first.parentNode
    }
  }

  indexOf(parent, child){ return Array.from(parent.children).indexOf(child) }
}
